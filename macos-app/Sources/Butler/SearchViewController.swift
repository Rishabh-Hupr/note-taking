import AppKit

// SearchViewController is the overlay's content: a blurred panel with a search
// field on top and a results list below. Typing runs a live fetch; Up/Down move
// the selection while the field keeps focus; Enter copies; Esc dismisses.
@MainActor
final class SearchViewController: NSViewController {
    private let sidecar: SidecarClient
    var onDismiss: (() -> Void)?

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private var results: [Note] = []
    private var searchTask: Task<Void, Never>?

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

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
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

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let notes = try await sidecar.fetch(query)
                if Task.isCancelled { return }
                self.results = notes
                self.tableView.reloadData()
                if !notes.isEmpty { self.select(row: 0) }
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
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
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
        cell.configure(with: results[row])
        return cell
    }

    // Table shouldn't grab first responder; keep focus in the search field.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
    func selectionShouldChange(in tableView: NSTableView) -> Bool { false }
}

// A two-line cell: key (bold) over a truncated value preview.
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

    func configure(with note: Note) {
        keyLabel.stringValue = note.key
        valueLabel.stringValue = note.value.replacingOccurrences(of: "\n", with: " ")
    }
}
