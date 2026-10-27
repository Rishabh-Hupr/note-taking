import AppKit
import Testing
@testable import Butler

// Regression tests for "selected note still ends in …": row heights are computed
// from a text measurement, so the measurement must use the width the cell really
// wraps at, and the formula must cover everything the cell lays out.
@MainActor
@Suite struct SearchRowLayoutTests {
    private final class DataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            NSTableCellView()
        }
    }

    @Test func cellsSpanTheFullScrollWidth() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 30, width: 616, height: 300))
        let table = NSTableView()
        SearchViewController.configureResultsTable(table)
        let source = DataSource()
        table.dataSource = source
        table.delegate = source
        scroll.documentView = table
        window.contentView?.addSubview(scroll)
        table.reloadData()
        window.contentView?.layoutSubtreeIfNeeded()
        table.sizeLastColumnToFit()
        table.layoutSubtreeIfNeeded()

        let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        // The default .inset style made this ~584 against a 616pt scroll area.
        #expect(cell?.frame.width == scroll.contentView.bounds.width)
    }

    @Test(arguments: [616.0, 480.0])
    func expandedRowHeightCoversCellContent(width: CGFloat) {
        _ = NSApplication.shared
        let font = NSFont.systemFont(ofSize: 12)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let sentence = "The quick brown fox jumps over the lazy dog, again and again. "

        // Notes from 1 to ~8 wrapped lines: the range shown fully inline.
        for repeats in [1, 2, 4, 7, 10, 14, 18] {
            let note = Note(id: repeats, key: "key \(repeats)",
                            value: String(repeating: sentence, count: repeats),
                            createdAt: "", updatedAt: "2026-09-12T17:35:00Z", rank: 0)
            let valueHeight = OverlayLayout.textHeight(
                note.value, width: NoteCellView.textWidth(forCellWidth: width), font: font)
            guard !OverlayLayout.exceedsLines(textHeight: valueHeight, lineHeight: lineHeight, limit: 8)
            else { continue } // longer notes are truncated inline by design

            let rowHeight = OverlayLayout.expandedRowHeight(
                valueHeight: valueHeight, lineHeight: lineHeight, inlineLimit: 8)

            let cell = NoteCellView(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))
            cell.configure(with: note, expanded: true, animated: false,
                           maxCharsPerLine: OverlayLayout.maxCharsPerLine(
                               width: width, narrowestAdvance: OverlayLayout.narrowestAdvance(font)))
            cell.widthAnchor.constraint(equalToConstant: width).isActive = true
            cell.layoutSubtreeIfNeeded()
            let needed = cell.fittingSize.height

            #expect(needed <= rowHeight + 0.5,
                    "\(repeats)x sentence at \(width)pt needs \(needed)pt, row is \(rowHeight)pt")
        }
    }
}
