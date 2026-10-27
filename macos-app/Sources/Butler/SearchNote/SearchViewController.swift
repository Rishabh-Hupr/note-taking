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

    // Row heights: every row is one line, except a selected short note (up to
    // `inlineLineLimit` lines), which grows to show all of it. A longer note stays
    // one line (ending in "…") and opens in the side preview instead: showing its
    // first lines inline as well was the same text twice.
    private let collapsedHeight: CGFloat = 48
    private let maxExpandedHeight: CGFloat = 240
    static let inlineLineLimit = 8
    private let valueFont = OverlayLayout.noteFont
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

    /// The most recently saved note, if the recent-notes list is loaded.
    var newestNote: Note? { recentNotes?.first }

    // Row heights and what each row's label gets both depend on the row's text
    // width, which is unknown before the first layout (rows are then set up as
    // one-liners). When it arrives or changes, redo the visible rows.
    private var laidOutRowTextWidth: CGFloat?

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = rowTextWidth()
        guard width != laidOutRowTextWidth else { return }
        laidOutRowTextWidth = width
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        let rows = IndexSet(integersIn: visible.location..<NSMaxRange(visible))
        tableView.noteHeightOfRows(withIndexesChanged: rows)
        for r in rows {
            if let cell = tableView.view(atColumn: 0, row: r, makeIfNecessary: false) as? NoteCellView {
                configure(cell, row: r, animated: false)
            }
        }
    }

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
                configure(cell, row: r, animated: r == current)
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
              isLong(results[row]) == true else {
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
        configure(cell, row: row, animated: false)
        return cell
    }

    // The one place a row's look is decided: expanded only when selected and short.
    private func configure(_ cell: NoteCellView, row: Int, animated: Bool) {
        guard row >= 0, row < results.count else { return }
        let expanded = row == tableView.selectedRow && expandsInline(results[row])
        cell.configure(with: results[row], expanded: expanded, animated: animated && expanded,
                       maxCharsPerLine: rowMaxCharsPerLine())
    }

    // The selected row grows to show a short note; everything else is one line.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < results.count, row == tableView.selectedRow,
              expandsInline(results[row]), let valueHeight = inlineValueHeight(results[row]) else {
            return collapsedHeight
        }
        // Key line + the whole (short) value + padding.
        let total = OverlayLayout.expandedRowHeight(
            valueHeight: valueHeight, lineHeight: valueLineHeight, inlineLimit: Self.inlineLineLimit)
        return min(max(collapsedHeight, total), expandedHeightCap())
    }

    // A selected note is shown inline when it's known to be short.
    private func expandsInline(_ note: Note) -> Bool { isLong(note) == false }

    // Whether the note wraps to more lines than a row shows inline; nil before
    // the table has been laid out.
    private func isLong(_ note: Note) -> Bool? {
        inlineValueHeight(note).map {
            OverlayLayout.exceedsLines(textHeight: $0, lineHeight: valueLineHeight, limit: Self.inlineLineLimit)
        }
    }

    // The value's height at the current column width, measured from its start
    // only (exact for a short note; over the limit for a long one), or nil before
    // the table has been laid out.
    private func inlineValueHeight(_ note: Note) -> CGFloat? {
        guard let width = rowTextWidth() else { return nil }
        return OverlayLayout.leadingTextHeight(
            note.value, lines: Self.inlineLineLimit, width: width, font: valueFont,
            maxCharsPerLine: rowMaxCharsPerLine())
    }

    // The most characters a row's line can hold, from the row's real text
    // width. Before layout, the widest screen bounds it.
    private func rowMaxCharsPerLine() -> Int {
        let width = rowTextWidth() ?? NSScreen.screens.map(\.frame.width).max() ?? 4096
        return OverlayLayout.maxCharsPerLine(width: width, narrowestAdvance: OverlayLayout.noteFontNarrowestAdvance)
    }

    // The width a row's value wraps at, or nil before the table has been laid out.
    private func rowTextWidth() -> CGFloat? {
        // Cells are exactly the scroll area's width (.plain style), so the label
        // wraps at the cell's text width for that (margins and timestamp column off).
        // Measure against the clip view's width (the actual content area), not the
        // table's bounds: when a vertical scroller is shown it narrows the usable
        // width, and measuring too wide would under-count wrapped lines and clip
        // the bottom of a long note. Before layout the width is ~0, so stay
        // collapsed; the next layout re-queries this with the true width.
        let contentWidth = tableView.enclosingScrollView?.contentView.bounds.width ?? tableView.bounds.width
        guard contentWidth > 120 else { return nil }
        return NoteCellView.textWidth(forCellWidth: contentWidth)
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

    // The "when" column at the row's right end (see NoteTimestamp).
    static let timestampDayFont = NSFont.systemFont(ofSize: 11)
    static let timestampTimeFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
    static let timestampGap: CGFloat = 12
    /// Closer to the row's right edge than the text margin: just inside the
    /// rounded selection highlight (inset 10pt).
    static let timestampTrailingMargin: CGFloat = 16
    /// The timestamp as drawn: the day, with the time under it a little smaller,
    /// right-aligned (an attributed string's own alignment beats the label's).
    static func timestampText(day: String, time: String) -> NSAttributedString {
        let right = NSMutableParagraphStyle()
        right.alignment = .right
        let quiet: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: right]
        let text = NSMutableAttributedString(string: day + "\n", attributes: quiet.merging([.font: timestampDayFont]) { $1 })
        text.append(NSAttributedString(string: time, attributes: quiet.merging([.font: timestampTimeFont]) { $1 }))
        return text
    }

    /// Wide enough for any timestamp: the widest day (date, weekday) with the
    /// widest time, measured as drawn.
    static let timestampColumnWidth: CGFloat = {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let days = months.map { "28 \($0) 2088" } + weekdays + ["Today", "Yesterday"]
        return ceil(days.flatMap { day in ["12:59 AM", "12:59 PM"].map { timestampText(day: day, time: $0) } }
            .map { $0.size().width }.max() ?? 0)
    }()

    /// The width a row's key and value wrap at, in a cell `cellWidth` wide: the
    /// cell minus its margins and the timestamp column. The controller measures
    /// with this and the label wraps at it, so the two can't disagree.
    static func textWidth(forCellWidth cellWidth: CGFloat) -> CGFloat {
        max(0, cellWidth - horizontalMargin - timestampGap - timestampColumnWidth - timestampTrailingMargin)
    }

    private let keyLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        keyLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        valueLabel.font = OverlayLayout.noteFont // what the controller measures with
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        // When a long value doesn't fit, the value (not the key) gives up space and
        // its last visible line ends in "…".
        valueLabel.cell?.truncatesLastVisibleLine = true
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        keyLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        timestampLabel.font = Self.timestampDayFont // colours and alignment: see timestampText
        timestampLabel.maximumNumberOfLines = 2 // day, then time
        timestampLabel.lineBreakMode = .byClipping
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timestampLabel)

        let stack = NSStackView(views: [keyLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Pinned to the top (not centered): a centered stack taller than its row
        // overflows both edges, pushing the key out of view on long notes. The
        // timestamp's day sits on the key's line and its time under it, right-
        // aligned in a fixed-width column.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalMargin),
            stack.trailingAnchor.constraint(equalTo: timestampLabel.leadingAnchor, constant: -Self.timestampGap),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),
            timestampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.timestampTrailingMargin),
            timestampLabel.widthAnchor.constraint(equalToConstant: Self.timestampColumnWidth),
            timestampLabel.firstBaselineAnchor.constraint(equalTo: keyLabel.firstBaselineAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        // Wrap the value at the cell's real width so its height is measured correctly.
        valueLabel.preferredMaxLayoutWidth = Self.textWidth(forCellWidth: bounds.width)
        super.layout()
    }

    /// `expanded` shows the whole value and is only used for short notes (see
    /// SearchViewController.expandsInline). Collapsed shows one line, given only
    /// two lines' worth (`maxCharsPerLine`), so a long note costs no more to show:
    /// a label lays out and draws all the text it's given, visible or not.
    func configure(with note: Note, expanded: Bool, animated: Bool, maxCharsPerLine: Int) {
        keyLabel.stringValue = note.key
        if let when = NoteTimestamp.parts(updatedAt: note.updatedAt) {
            timestampLabel.attributedStringValue = Self.timestampText(day: when.day, time: when.time)
        } else {
            timestampLabel.stringValue = ""
        }
        if expanded {
            valueLabel.lineBreakMode = .byWordWrapping
            valueLabel.maximumNumberOfLines = 0
            valueLabel.stringValue = note.value
            valueLabel.textColor = .labelColor
        } else {
            valueLabel.lineBreakMode = .byTruncatingTail
            valueLabel.maximumNumberOfLines = 1
            valueLabel.stringValue = OverlayLayout.oneLineSummary(note.value, maxCharsPerLine: maxCharsPerLine)
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
