import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var panel: OverlayPanel?
    private var viewController: SearchViewController?
    private var sidecar: SidecarClient!

    // Allow construction from the nonisolated top-level (main.swift). All real
    // setup happens in applicationDidFinishLaunching, which stays main-actor.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        sidecar = SidecarClient(binaryURL: resolveSidecarBinary(), dataDir: nil)
        do {
            try sidecar.start()
        } catch {
            NSLog("Butler: failed to launch sidecar: \(error)")
        }

        buildPanel()

        // ⌘⌥Space summons the overlay.
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | optionKey),
            handler: { [weak self] in self?.toggle() }
        )
        if hotKey == nil {
            NSLog("Butler: failed to register global hotkey")
        }

        // Hide when the user clicks away.
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: nil
        )
    }

    // MARK: - Panel

    private func buildPanel() {
        let vc = SearchViewController(sidecar: sidecar)
        vc.onDismiss = { [weak self] in self?.hide() }

        let overlayPanel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400))
        overlayPanel.contentViewController = vc

        self.viewController = vc
        self.panel = overlayPanel
    }

    private func toggle() {
        guard let panel else { return }
        if panel.isVisible { hide() } else { show() }
    }

    private func show() {
        guard let panel, let viewController else { return }
        positionOnActiveScreen(panel)
        viewController.prepareForShow()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    @objc private func panelResignedKey(_ note: Notification) {
        guard let panel, (note.object as? NSWindow) === panel else { return }
        hide()
    }

    // Center horizontally, upper third vertically, on whichever screen has the mouse.
    private func positionOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY + frame.height * 0.12 // a bit above center, Spotlight-style
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Sidecar binary resolution

    // Dev: set BUTLER_CORE_BIN to the built binary. Falls back to the sibling
    // go-rewrite build, then to a bundled Resources copy (for a packaged .app).
    private func resolveSidecarBinary() -> URL {
        if let env = ProcessInfo.processInfo.environment["BUTLER_CORE_BIN"] {
            return URL(fileURLWithPath: env)
        }
        if let bundled = Bundle.main.url(forResource: "butler-core", withExtension: nil) {
            return bundled
        }
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd)
            .appendingPathComponent("../go-rewrite/butler-core")
            .standardizedFileURL
    }
}
