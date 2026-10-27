import AppKit

// NotePreviewPanel shows the full text of a long note beside the search overlay.
// It never becomes key, so focus (and ↑/↓, ⏎, ⌘D) stays in the search field;
// trackpad scrolling still works because scroll events go to the window under the
// cursor regardless of key status.
@MainActor
final class NotePreviewPanel: NSPanel {
    static let preferredWidth: CGFloat = 420
    static let minWidth: CGFloat = 300
    private let padding: CGFloat = 16
    private let maxKeyLines = 3
    private let keyFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private var keyHeightConstraint: NSLayoutConstraint?
    private let headerSpacing: CGFloat = 8
    // The preview grows to fit up to this many lines, then scrolls.
    private let maxVisibleLines = 50
    // Strip reserved on the right for the scroller so it never sits on the text.
    private let scrollerGutter: CGFloat = 14
    private func textWidth(forPanelWidth width: CGFloat) -> CGFloat {
        width - padding * 2 - scrollerGutter
    }
    private let textFont = OverlayLayout.noteFont
    private lazy var lineHeight = NSLayoutManager().defaultLineHeight(for: textFont)
    private lazy var keyLineHeight = NSLayoutManager().defaultLineHeight(for: keyFont)
    private var oneKeyLine: CGFloat { ceil(keyLineHeight) } // the header's minimum height

    private let keyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var shownNoteID: Int?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect

        keyLabel.font = keyFont
        // The key wraps (up to maxKeyLines, then "…") and may never widen the
        // panel: a single-line label resists compression and pushed the window
        // past its planned width — over the search window, or off-screen.
        keyLabel.lineBreakMode = .byWordWrapping
        keyLabel.maximumNumberOfLines = maxKeyLines
        keyLabel.cell?.truncatesLastVisibleLine = true
        keyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = textFont
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        // Fixed wrap width (content minus the scroller gutter), independent of the
        // scroll view's width, so the scroller showing never re-wraps the text.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: textWidth(forPanelWidth: Self.preferredWidth), height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay // floats in the reserved gutter
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(keyLabel)
        effect.addSubview(scrollView)
        let keyHeight = keyLabel.heightAnchor.constraint(equalToConstant: oneKeyLine)
        keyHeightConstraint = keyHeight
        NSLayoutConstraint.activate([
            keyLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: padding),
            keyLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding),
            keyLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -padding),
            keyHeight,

            scrollView.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: headerSpacing),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -padding),
            scrollView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -padding),
        ])
    }

    /// True while the text view uses TextKit 2 (lays out only what's visible).
    var usesViewportLayout: Bool { textView.textLayoutManager != nil }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show `note` beside `parent`, top-aligned with `anchor` (the selected row, in
    /// screen coordinates). Slides + fades in the first time; afterwards it just
    /// glides to the new position and swaps content.
    func present(_ note: Note, anchor: NSRect, in parent: NSWindow) {
        let isNewNote = note.id != shownNoteID
        shownNoteID = note.id
        keyLabel.stringValue = note.key

        // Decide side + width first (the text wraps at it), then height comes only
        // from the text and that width — never from the text view's current
        // layout — so the same note on the same screen always gets the same size.
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let (x, width, slideFrom) = OverlayLayout.previewHorizontal(
            parent: parent.frame, visible: visible,
            preferredWidth: Self.preferredWidth, minWidth: Self.minWidth)
        let wrapWidth = textWidth(forPanelWidth: width)
        // Measured from the note's start only: the panel shows at most
        // maxVisibleLines before scrolling, so the rest can't change its size.
        let textHeight = OverlayLayout.leadingTextHeight(
            note.value, lines: maxVisibleLines, width: wrapWidth, font: textFont,
            maxCharsPerLine: OverlayLayout.maxCharsPerLine(
                width: wrapWidth, narrowestAdvance: OverlayLayout.noteFontNarrowestAdvance))
        let textAreaHeight = OverlayLayout.previewTextAreaHeight(
            textHeight: textHeight, lineHeight: lineHeight, maxLines: maxVisibleLines)
        // Key height at this width (wrapped, capped at maxKeyLines) is part of the
        // panel height, so a long key can't push the panel off-screen either.
        let contentWidth = width - padding * 2
        // Measured by the label's own cell (its insets and padding make it wrap a
        // little narrower than a plain text measurement at the same width).
        let fitted = keyLabel.cell?.cellSize(forBounds: NSRect(
            x: 0, y: 0, width: contentWidth, height: .greatestFiniteMagnitude)).height ?? oneKeyLine
        let keyHeight = max(oneKeyLine,
                            OverlayLayout.cappedToLines(fitted, lineHeight: keyLineHeight, maxLines: maxKeyLines))
        keyLabel.preferredMaxLayoutWidth = contentWidth
        keyHeightConstraint?.constant = keyHeight
        let chrome = padding * 2 + keyHeight + headerSpacing
        let height = min(textAreaHeight + chrome, visible.height - 2 * OverlayLayout.screenMargin)
        let y = OverlayLayout.previewY(anchor: anchor, height: height, visible: visible)
        let target = NSRect(x: x, y: y, width: width, height: height)

        // The text view itself stays as tall as its content (that's the scroll range).
        // It holds the whole note but lays out only what's on screen (TextKit 2:
        // a 1.5MB note draws as fast as a 6KB one), and sizeToFit just estimates.
        textView.textContainer?.containerSize = NSSize(width: wrapWidth, height: .greatestFiniteMagnitude)
        textView.frame.size.width = width - padding * 2
        if isNewNote {
            textView.string = note.value
        }
        textView.sizeToFit()
        if isNewNote {
            textView.scroll(.zero)
        }

        let alreadyShown = isVisible && self.parent === parent
        if !alreadyShown {
            setFrame(target.offsetBy(dx: slideFrom, dy: 0), display: false)
            alphaValue = 0
            parent.addChildWindow(self, ordered: .above)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = alreadyShown ? 0.14 : 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        }
    }

    /// Fade out, then detach from the parent.
    func dismissAnimated() {
        shownNoteID = nil
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // If a new note was presented during the fade, keep it on screen.
                guard let self, self.shownNoteID == nil else { return }
                self.detach()
            }
        })
    }

    /// Remove immediately (e.g. the overlay itself is closing).
    func hideNow() {
        shownNoteID = nil
        detach()
    }

    private func detach() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}
