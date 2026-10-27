import AppKit

// Pure geometry/sizing rules for the overlays, kept free of view state so they're
// deterministic and unit-testable. The views call into these.
enum OverlayLayout {
    /// Minimum distance kept between any overlay and the screen's visible edges.
    static let screenMargin: CGFloat = 8
    /// Gap between the search window and the side preview.
    static let previewGap: CGFloat = 10
    /// Extra height so text that exactly fits isn't clipped or given a scroller
    /// by rounding (and covers a label cell's own insets).
    static let lineSlack: CGFloat = 2

    /// Height of `text` wrapped at `width` in `font`.
    ///
    /// Laid out with TextKit rather than `NSString.boundingRect`: the heights are
    /// identical (except "", 14pt here versus 15; empty notes can't be saved),
    /// but boundingRect slows down sharply on long notes: 145ms for a 6KB,
    /// 116-line note versus 2.6ms here, and a selection measured its note 3 times.
    static func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0 // boundingRect has none either
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    /// The font note text is shown in: the search rows and the side preview.
    static let noteFont = NSFont.systemFont(ofSize: 12)
    /// `noteFont`'s narrowest character (see narrowestAdvance), measured once.
    static let noteFontNarrowestAdvance = narrowestAdvance(noteFont)

    /// Advance of the narrowest printable ASCII character in `font` (in the
    /// system font, "i"/"l"/"'" are the narrowest characters, at about 0.24em).
    static func narrowestAdvance(_ font: NSFont) -> CGFloat {
        (32...126).map { code in
            (String(UnicodeScalar(UInt8(code))) as NSString).size(withAttributes: [.font: font]).width
        }.filter { $0 > 0 }.min() ?? 1
    }

    /// More characters than one line `width` wide can hold, even all in the
    /// narrowest character.
    static func maxCharsPerLine(width: CGFloat, narrowestAdvance: CGFloat) -> Int {
        Int((width / narrowestAdvance).rounded(.up)) + 1
    }

    /// The start of `text`: its first `lines + 1` lines, cut to at most
    /// `maxCharsPerLine` × (`lines` + 2) characters. Short enough that measuring
    /// it costs the same for any note, and long enough to decide everything the
    /// screen needs: if `text` wraps to more than `lines` lines, so does this.
    /// (Either it's all of `text`, or it has `lines + 1` lines, or it has more
    /// characters than `lines + 1` lines can hold; the + 2 leaves room for the
    /// line breaks themselves.) Known, accepted gap: that assumes every character
    /// takes room, so a huge run of spaces (which hang at a line's end) or
    /// zero-width characters early in a note could make a long note look short:
    /// it would then expand inline instead of opening the preview. Not seen in
    /// real notes; if it ever is, re-measure with a doubled excerpt until it
    /// overflows or covers the whole note.
    static func leadingExcerpt(_ text: String, lines: Int, maxCharsPerLine: Int) -> Substring {
        let capped = text.prefix(maxCharsPerLine * (lines + 2))
        var breaks = 0
        // isNewline covers every break TextKit wraps on: \n, \r\n, \r, U+2028…
        guard let end = capped.firstIndex(where: { char in
            if char.isNewline { breaks += 1 }
            return breaks > lines
        }) else { return capped }
        return capped[..<end]
    }

    /// Height of `text` as `textHeight` would measure it, as long as that's at
    /// most `lines` lines; for longer text, some height over `lines` lines. That's
    /// all a capped view needs (does it fit? how tall up to the cap?), and only
    /// the start of the note is laid out, so a 1MB note costs what a short one does.
    static func leadingTextHeight(_ text: String, lines: Int, width: CGFloat, font: NSFont,
                                  maxCharsPerLine: Int) -> CGFloat {
        textHeight(String(leadingExcerpt(text, lines: lines, maxCharsPerLine: maxCharsPerLine)),
                   width: width, font: font)
    }

    /// `text` on one line for a collapsed row: line breaks become spaces, and
    /// only two lines' worth is kept (the label shows one, then "…").
    static func oneLineSummary(_ text: String, maxCharsPerLine: Int) -> String {
        String(text.prefix(maxCharsPerLine * 2).map { $0.isNewline ? " " : $0 })
    }

    /// Selected search row: key line + value (up to `inlineLimit` lines) + padding.
    /// Must cover what NoteCellView actually lays out, or the value gets cut off.
    static func expandedRowHeight(valueHeight: CGFloat, lineHeight: CGFloat, inlineLimit: Int) -> CGFloat {
        let keyLineHeight: CGFloat = 20
        let verticalPadding: CGFloat = 22
        return keyLineHeight + ceil(min(valueHeight, lineHeight * CGFloat(inlineLimit))) + verticalPadding
    }

    /// True when text of `textHeight` wraps to more than `limit` lines.
    static func exceedsLines(textHeight: CGFloat, lineHeight: CGFloat, limit: Int) -> Bool {
        textHeight > lineHeight * CGFloat(limit) + 1
    }

    /// Height that fits `contentHeight` but at most `maxLines` lines, plus
    /// `lineSlack`. Used for the preview's text area (which scrolls past the cap)
    /// and its key (which ends in "…" past the cap), so both cap the same way.
    static func cappedToLines(_ contentHeight: CGFloat, lineHeight: CGFloat, maxLines: Int) -> CGFloat {
        min(ceil(contentHeight), ceil(lineHeight * CGFloat(maxLines))) + lineSlack
    }

    /// Preview text area: fits the text up to `maxLines`, then stays at that cap
    /// (and scrolls).
    static func previewTextAreaHeight(textHeight: CGFloat, lineHeight: CGFloat, maxLines: Int) -> CGFloat {
        cappedToLines(textHeight, lineHeight: lineHeight, maxLines: maxLines)
    }

    /// Horizontal placement for the preview beside `parent`: on whichever side has
    /// more room (right on a tie), at the preferred width or narrowed to that room
    /// (but not below `minWidth`), so it doesn't sit on top of the parent. Width is
    /// decided first because the text wraps at it. `slideFrom` is the x-offset to
    /// animate in from (toward the parent).
    static func previewHorizontal(
        parent: NSRect, visible: NSRect, preferredWidth: CGFloat, minWidth: CGFloat,
        gap: CGFloat = previewGap, margin: CGFloat = screenMargin
    ) -> (x: CGFloat, width: CGFloat, slideFrom: CGFloat) {
        let rightRoom = visible.maxX - margin - (parent.maxX + gap)
        let leftRoom = parent.minX - gap - (visible.minX + margin)
        let useRight = rightRoom >= leftRoom
        let room = useRight ? rightRoom : leftRoom
        let width = max(minWidth, min(preferredWidth, room))
        var x = useRight ? parent.maxX + gap : parent.minX - gap - width
        // Only when even minWidth doesn't fit does it overlap the parent.
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
        // Slide in from just under the gap away, so even the first frame never
        // touches the search window.
        let slide = gap * 0.8
        return (x, width, useRight ? -slide : slide)
    }

    /// Vertical placement: top-aligned with `anchor` (the selected row), clamped.
    static func previewY(anchor: NSRect, height: CGFloat, visible: NSRect, margin: CGFloat = screenMargin) -> CGFloat {
        min(max(anchor.maxY - height, visible.minY + margin), visible.maxY - height - margin)
    }

    /// A remembered panel origin, clamped onto the screen it overlaps — or nil if
    /// it overlaps no current screen (e.g. that display was unplugged).
    static func restoredOrigin(_ saved: NSPoint, size: NSSize, screens: [NSRect]) -> NSPoint? {
        let rect = NSRect(origin: saved, size: size)
        guard let vf = screens.first(where: { $0.intersects(rect) }) else { return nil }
        return NSPoint(
            x: min(max(saved.x, vf.minX), vf.maxX - size.width),
            y: min(max(saved.y, vf.minY), vf.maxY - size.height)
        )
    }

    /// Default placement: centered horizontally, a bit above center, clamped.
    static func defaultOrigin(size: NSSize, visible vf: NSRect, margin: CGFloat = screenMargin) -> NSPoint {
        let x = vf.midX - size.width / 2
        let y = vf.midY + vf.height * 0.12
        return NSPoint(
            x: min(max(x, vf.minX + margin), vf.maxX - size.width - margin),
            y: min(max(y, vf.minY + margin), vf.maxY - size.height - margin)
        )
    }
}
