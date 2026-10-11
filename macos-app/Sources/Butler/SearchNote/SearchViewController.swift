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
    private let defaultHint = "↑↓ navigate    ⏎ copy    ⌘D delete    ⎋ close"
    // Bumped per hint flash, so an older flash's timer can't restore the hints
    // over a newer message.
    private var hintGeneration = 0
    private var results: [Note] = []
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let loadingDots = LoadingDots()
    // How long typing must pause before the search runs.
    private static let typingDebounce: UInt64 = 100_000_000

    // Row heights: every row is one line, except the selected one, which grows to
    // fit its value up to `inlineLineLimit` lines. Longer notes show those lines
    // inline (ending in "…") and open the full text in the side preview.
    private let collapsedHeight: CGFloat = 48
    private let maxExpandedHeight: CGFloat = 240
    private let inlineLineLimit = 8
    private let valueFont = NSFont.systemFont(ofSize: 12)
    private lazy var valueLineHeight = NSLayoutManager().defaultLineHeight(for: valueFont)
    private let preview = NotePreviewPanel()

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
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 592) // ~4 more rows than 400

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search notes…"
        searchField.font = .systemFont(ofSize: 22, weight: .light)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.onCommandD = { [weak self] in self?.deleteSelected() }
        view.addSubview(searchField)
        view.addSubview(loadingDots)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        Self.configureResultsTable(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        scroll.documentView = tableView
        view.addSubview(scroll)

        // Persistent shortcut hint, mirroring the Put dialog's footer so the
        // available actions (notably ⌘D to delete) are always discoverable.
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.stringValue = defaultHint
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: loadingDots.leadingAnchor, constant: -8),
            loadingDots.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            loadingDots.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            loadingDots.widthAnchor.constraint(equalToConstant: 34),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -8),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        // The overlay hides when it loses key (click-away, ⌘⌥P); take the preview
        // down with it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey(_:)),
            name: NSWindow.didResignKeyNotification, object: nil
        )
    }

    @objc private func windowResignedKey(_ note: Notification) {
        guard (note.object as? NSWindow) === view.window else { return }
        previewTask?.cancel()
        preview.hideNow()
    }

    // Close the overlay (copy / Esc), taking the preview with it.
    private func dismiss() {
        previewTask?.cancel()
        preview.hideNow()
        onDismiss?()
    }

    /// Results table setup. Separate (and static) so tests can check the geometry
    /// that row-height measurement relies on.
    static func configureResultsTable(_ table: NSTableView) {
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 48
        table.selectionHighlightStyle = .regular
        // .plain + no horizontal spacing makes each cell exactly the scroll area's
        // width. The default (.inset) silently pads rows by ~16pt a side, so row
        // heights measured at the scroll width under-counted wrapped lines and cut
        // long notes off with "…". Margins and the rounded highlight are drawn by
        // NoteCellView / RoundedSelectionRowView instead.
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: table.intercellSpacing.height)
        let column = NSTableColumn(identifier: .init("note"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    // In-memory copy of the empty-query result (the most recent notes), so opening
    // search fills the list without a backend round trip. Kept current by
    // refreshRecent() after saves/deletes; nil until the first fetch lands.
    private var recentNotes: [Note]?

    // Called by AppDelegate each time the panel is summoned.
    func prepareForShow() {
        previewTask?.cancel()
        preview.hideNow()
        loadingDots.stop()
        resetHint()
        searchField.stringValue = ""
        // Let the window appear first, exactly as before: an empty list is cheap to
        // draw. Filling + laying out the list takes ~150-200ms, and doing it here
        // (before the first frame) delayed the window itself on every ⌘⌥F.
        results = []
        tableView.reloadData()
        if recentNotes != nil {
            // Fill from memory on the next run-loop turn — after the window is up,
            // with no backend round trip.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.searchField.stringValue.isEmpty, let cached = self.recentNotes else { return }
                self.results = cached
                self.tableView.reloadData()
                if !cached.isEmpty { self.select(row: 0) }
                self.revalidateRecent()
            }
        } else {
            runSearch("") // empty → lists all (recent first)
        }
        view.window?.makeFirstResponder(searchField)
    }

    /// Re-fetch the recent-notes cache in the background (after a save or delete,
    /// and at launch). Doesn't touch what's on screen.
    func refreshRecent() {
        Task { [weak self] in
            guard let self, let notes = try? await self.sidecar.fetch("") else { return }
            self.recentNotes = notes
        }
    }

    // Safety net on open: if the backend's list differs from the cache (e.g. the
    // backend was hot-swapped), update it — and the screen, if still unfiltered.
    // Identical lists change nothing, so there's no redraw.
    private func revalidateRecent() {
        Task { [weak self] in
            guard let self, let notes = try? await self.sidecar.fetch("") else { return }
            guard notes != self.recentNotes else { return }
            self.recentNotes = notes
            guard self.searchField.stringValue.isEmpty, self.view.window?.isVisible == true else { return }
            let keep = max(0, self.tableView.selectedRow)
            self.results = notes
            self.tableView.reloadData()
            if !notes.isEmpty { self.select(row: min(keep, notes.count - 1)) }
        }
    }

    // MARK: - Search

    private func runSearch(_ query: String, selecting preferredRow: Int = 0) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let notes = try await sidecar.fetch(query)
                if Task.isCancelled { return }
                self.loadingDots.stop()
                if query.isEmpty { self.recentNotes = notes }
                self.results = notes
                self.tableView.reloadData()
                if notes.isEmpty {
                    self.preview.dismissAnimated()
                } else {
                    self.select(row: min(max(0, preferredRow), notes.count - 1))
                }
            } catch {
                // Transient (e.g. sidecar restarting): clear results for now.
                if Task.isCancelled { return }
                self.loadingDots.stop()
                self.results = []
                self.tableView.reloadData()
                self.preview.dismissAnimated()
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
        schedulePreview(for: current)
    }

    // The preview follows the selection only once it settles for 0.1s, so holding
    // ↑/↓ doesn't open/close it on every row passed; it updates once on stopping.
    private var previewTask: Task<Void, Never>?

    private func schedulePreview(for row: Int) {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self, !Task.isCancelled, self.tableView.selectedRow == row else { return }
            self.updatePreview(for: row)
        }
    }

    // Long notes get the full text in the side preview; short ones close it.
    private func updatePreview(for row: Int) {
        guard row >= 0, row < results.count,
              let window = view.window, window.isVisible,
              exceedsInlineLimit(results[row]) else {
            preview.dismissAnimated()
            return
        }
        // Anchor to the part of the row that's actually on screen.
        var rowRect = tableView.rect(ofRow: row).intersection(tableView.visibleRect)
        if rowRect.isEmpty { rowRect = tableView.visibleRect }
        let onScreen = window.convertToScreen(tableView.convert(rowRect, to: nil))
        preview.present(results[row], anchor: onScreen, in: window)
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(results.count - 1, current + delta))
        // Holding ↑/↓ at either end keeps landing on the same row; re-selecting it
        // replayed the fade and re-attached the preview ~30×/s (flicker).
        guard next != current else { return }
        select(row: next)
    }

    private func copySelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(results[row].value, forType: .string)
        dismiss()
    }

    // ⌘D: delete the selected note, then refresh and keep the cursor near where it
    // was (the row that slid up into the deleted slot).
    private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        let id = results[row].id
        let key = results[row].key
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sidecar.delete(id: id)
                self.runSearch(self.searchField.stringValue, selecting: row)
                self.refreshRecent() // deleted note must leave the cached recent list
                self.flashHint("🗑  Deleted “\(key)”", color: .systemRed)
            } catch {
                // Leave the list as-is; the response logging captures why.
                self.flashHint("Delete failed — try again", color: .systemRed)
            }
        }
    }

    // Briefly replace the shortcut hints with a confirmation, then restore them.
    private func flashHint(_ message: String, color: NSColor, seconds: Double = 1.5) {
        hintGeneration += 1
        let generation = hintGeneration
        hintLabel.stringValue = message
        hintLabel.textColor = color
        hintLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, generation == self.hintGeneration else { return }
            self.resetHint()
        }
    }

    private func resetHint() {
        hintGeneration += 1
        hintLabel.stringValue = defaultHint
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)
    }
}

// MARK: - Text field: live search + key handling

extension SearchViewController: NSTextFieldDelegate {
    // Debounce: wait until typing pauses before searching. Searching on every
    // keystroke re-ran the row-grow animation and the preview fade per character,
    // which made typing feel laggy.
    func controlTextDidChange(_ obj: Notification) {
        debounceTask?.cancel()
        let query = searchField.stringValue
        // Field cleared: the result is the recent-notes list we already hold, so
        // show it now — no debounce wait, no round trip (revalidated in background).
        if query.isEmpty, let cached = recentNotes {
            searchTask?.cancel() // a typed search still in flight mustn't overwrite this
            loadingDots.stop()
            results = cached
            tableView.reloadData()
            if !cached.isEmpty { select(row: 0) }
            revalidateRecent()
            return
        }
        loadingDots.start() // shown through the debounce wait and the fetch
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.typingDebounce)
            guard !Task.isCancelled else { return }
            self?.runSearch(query)
        }
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
            dismiss(); return true
        default:
            return false
        }
    }
}

// MARK: - Table data + cells

extension SearchViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedSelectionRowView()
    }

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

    // Size the selected row to show its value (key line + value + padding), up to
    // `inlineLineLimit` lines; anything longer is read in the side preview.
    private func expandedHeight(for note: Note) -> CGFloat {
        guard let valueHeight = measuredValueHeight(note) else { return collapsedHeight }
        let total = OverlayLayout.expandedRowHeight(
            valueHeight: valueHeight, lineHeight: valueLineHeight, inlineLimit: inlineLineLimit)
        return min(max(collapsedHeight, total), expandedHeightCap())
    }

    // True when the note wraps to more lines than the row shows inline.
    private func exceedsInlineLimit(_ note: Note) -> Bool {
        guard let valueHeight = measuredValueHeight(note) else { return false }
        return OverlayLayout.exceedsLines(
            textHeight: valueHeight, lineHeight: valueLineHeight, limit: inlineLineLimit)
    }

    // Height of the value wrapped at the current column width, or nil before the
    // table has been laid out.
    private func measuredValueHeight(_ note: Note) -> CGFloat? {
        // Cells are exactly the scroll area's width (.plain style), so the label
        // wraps at that width minus the cell's own margins on both sides.
        let horizontalInset = NoteCellView.horizontalMargin * 2
        // Measure against the clip view's width (the actual content area), not the
        // table's bounds: when a vertical scroller is shown it narrows the usable
        // width, and measuring too wide would under-count wrapped lines and clip
        // the bottom of a long note. Before layout the width is ~0, so stay
        // collapsed; the next layout re-queries this with the true width.
        let contentWidth = tableView.enclosingScrollView?.contentView.bounds.width ?? tableView.bounds.width
        guard contentWidth > 120 else { return nil }
        return OverlayLayout.textHeight(
            note.value, width: contentWidth - horizontalInset, font: valueFont)
    }

    // Let a long note use the visible list area, minus one collapsed row so a
    // neighbour stays in view. Falls back to a fixed cap before first layout.
    private func expandedHeightCap() -> CGFloat {
        let visible = tableView.enclosingScrollView?.contentView.bounds.height ?? 0
        guard visible > collapsedHeight * 2 else { return maxExpandedHeight }
        return visible - collapsedHeight
    }

    // Table shouldn't grab first responder; keep focus in the search field.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
    func selectionShouldChange(in tableView: NSTableView) -> Bool { false }
}

// A cell with a key (bold) over a value. Collapsed it shows a one-line truncated
// preview; when its row is selected it shows the full wrapped value and fades in.
final class NoteCellView: NSTableCellView {
    /// Text margin inside the cell, each side (matches the old .inset look: 16pt
    /// row inset + 8pt stack padding).
    static let horizontalMargin: CGFloat = 24

    private let keyLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        keyLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        // When a long value doesn't fit, the value (not the key) gives up space and
        // its last visible line ends in "…".
        valueLabel.cell?.truncatesLastVisibleLine = true
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        keyLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = NSStackView(views: [keyLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Pinned to the top (not centered): a centered stack taller than its row
        // overflows both edges, pushing the key out of view on long notes.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalMargin),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalMargin),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        // Wrap the value at the cell's real width so its height is measured correctly.
        valueLabel.preferredMaxLayoutWidth = max(0, bounds.width - Self.horizontalMargin * 2)
        super.layout()
    }

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

// Draws the selection as a rounded, inset highlight — the look .inset style gave
// for free — while the row itself spans the full width (see tableView.style).
final class RoundedSelectionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let color: NSColor = isEmphasized
            ? .selectedContentBackgroundColor
            : .unemphasizedSelectedContentBackgroundColor
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}
