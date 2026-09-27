import AppKit

// SearchField intercepts ⌘D (delete selected note) even while the field is being
// edited: performKeyEquivalent is dispatched down the view tree regardless of who
// holds first responder, so text editing keeps working and ⌘D never touches the
// typed query.
final class SearchField: NSTextField {
    var onCommandD: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "d" {
            onCommandD?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// SearchViewController is the overlay's content: a blurred panel with a search
// field on top and a results list below. Typing runs a live fetch; Up/Down move
// the selection while the field keeps focus; Enter copies; ⌘D deletes; Esc
// dismisses. The selected note pops out to show its full content.
@MainActor
final class SearchViewController: NSViewController {
    private let sidecar: SidecarClient
    var onDismiss: (() -> Void)?

    private let searchField = SearchField()
    private let tableView = NSTableView()
    private let hintLabel = NSTextField(labelWithString: "")
    private var results: [Note] = []
    private var searchTask: Task<Void, Never>?

    // Row heights: every row is one line, except the selected one, which grows to
    // fit its full (multi-line) value, capped so a huge note can't fill the panel.
    private let collapsedHeight: CGFloat = 48
    private let maxExpandedHeight: CGFloat = 240

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        self.view = effect
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 400)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search notes…"
        searchField.font = .systemFont(ofSize: 22, weight: .light)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.onCommandD = { [weak self] in self?.deleteSelected() }
        view.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 48
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        let column = NSTableColumn(identifier: .init("note"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scroll.documentView = tableView
        view.addSubview(scroll)

        // Persistent shortcut hint, mirroring the Put dialog's footer so the
        // available actions (notably ⌘D to delete) are always discoverable.
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.stringValue = "↑↓ navigate    ⏎ copy    ⌘D delete    ⎋ close"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -8),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    // Called by AppDelegate each time the panel is summoned.
    func prepareForShow() {
        searchField.stringValue = ""
        results = []
        tableView.reloadData()
        runSearch("") // empty → lists all (recent first)
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Search

    private func runSearch(_ query: String, selecting preferredRow: Int = 0) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let notes = try await sidecar.fetch(query)
                if Task.isCancelled { return }
                self.results = notes
                self.tableView.reloadData()
                if !notes.isEmpty {
                    self.select(row: min(max(0, preferredRow), notes.count - 1))
                }
            } catch {
                // Transient (e.g. sidecar restarting): clear results for now.
                if Task.isCancelled { return }
                self.results = []
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Selection / actions

    private func select(row: Int) {
        guard row >= 0, row < results.count else { return }
        let previous = tableView.selectedRow
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        animateExpansion(from: previous, to: row)
    }

    // Pop the newly-selected row open (and collapse the previous one) with a quick
    // height + fade animation, then reconfigure both cells for their new state.
    private func animateExpansion(from previous: Int, to current: Int) {
        var changed = IndexSet(integer: current)
        if previous >= 0, previous < results.count, previous != current {
            changed.insert(previous)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.allowsImplicitAnimation = true
            tableView.noteHeightOfRows(withIndexesChanged: changed)
        }
        for r in changed {
            if let cell = tableView.view(atColumn: 0, row: r, makeIfNecessary: false) as? NoteCellView {
                cell.configure(with: results[r], expanded: r == current, animated: r == current)
            }
        }
        // Scroll only after the row has grown, so an expanding bottom row isn't
        // positioned by its old collapsed height and left clipped below the fold.
        tableView.scrollRowToVisible(current)
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(results.count - 1, current + delta))
        select(row: next)
    }

    private func copySelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(results[row].value, forType: .string)
        onDismiss?()
    }

    // ⌘D: delete the selected note, then refresh and keep the cursor near where it
    // was (the row that slid up into the deleted slot).
    private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        let id = results[row].id
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sidecar.delete(id: id)
                self.runSearch(self.searchField.stringValue, selecting: row)
            } catch {
                // Leave the list as-is on failure; the response logging captures why.
            }
        }
    }
}

// MARK: - Text field: live search + key handling

extension SearchViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        runSearch(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            copySelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?(); return true
        default:
            return false
        }
    }
}

// MARK: - Table data + cells

extension SearchViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NoteCellView) ?? {
            let c = NoteCellView()
            c.identifier = id
            return c
        }()
        cell.configure(with: results[row], expanded: row == tableView.selectedRow, animated: false)
        return cell
    }

    // The selected row grows to fit its full value; all others are one line.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < results.count, row == tableView.selectedRow else {
            return collapsedHeight
        }
        return expandedHeight(for: results[row])
    }

    // Measure the wrapped value text at the current column width and size the row
    // to show all of it (key line + value + padding), capped at maxExpandedHeight.
    private func expandedHeight(for note: Note) -> CGFloat {
        let horizontalInset: CGFloat = 16   // stack leading (8) + trailing (8)
        // Measure against the clip view's width (the actual content area), not the
        // table's bounds: when a vertical scroller is shown it narrows the usable
        // width, and measuring too wide would under-count wrapped lines and clip
        // the bottom of a long note. Before layout the width is ~0, so stay
        // collapsed; the next layout re-queries this with the true width.
        let contentWidth = tableView.enclosingScrollView?.contentView.bounds.width ?? tableView.bounds.width
        guard contentWidth > 120 else { return collapsedHeight }
        let width = contentWidth - horizontalInset
        let valueFont = NSFont.systemFont(ofSize: 12)
        let bounding = (note.value as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: valueFont])
        let keyLineHeight: CGFloat = 20
        let verticalPadding: CGFloat = 22
        let total = keyLineHeight + ceil(bounding.height) + verticalPadding
        return min(max(collapsedHeight, total), maxExpandedHeight)
    }

    // Table shouldn't grab first responder; keep focus in the search field.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
    func selectionShouldChange(in tableView: NSTableView) -> Bool { false }
}

// A cell with a key (bold) over a value. Collapsed it shows a one-line truncated
// preview; when its row is selected it shows the full wrapped value and fades in.
private final class NoteCellView: NSTableCellView {
    private let keyLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        keyLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [keyLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(with note: Note, expanded: Bool, animated: Bool) {
        keyLabel.stringValue = note.key
        if expanded {
            valueLabel.lineBreakMode = .byWordWrapping
            valueLabel.maximumNumberOfLines = 0
            valueLabel.stringValue = note.value
            valueLabel.textColor = .labelColor
        } else {
            valueLabel.lineBreakMode = .byTruncatingTail
            valueLabel.maximumNumberOfLines = 1
            valueLabel.stringValue = note.value.replacingOccurrences(of: "\n", with: " ")
            valueLabel.textColor = .secondaryLabelColor
        }

        // Quick fade so the full note feels like it "pops out" as you land on it.
        if animated && expanded {
            valueLabel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                valueLabel.animator().alphaValue = 1
            }
        } else {
            valueLabel.alphaValue = 1
        }
    }
}
