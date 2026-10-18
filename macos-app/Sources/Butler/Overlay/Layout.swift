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
    static func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]).height)
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
