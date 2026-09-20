import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fetchHotKey: GlobalHotKey?
    private var putHotKey: GlobalHotKey?
    private var fetchPanel: OverlayPanel?
    private var putPanel: OverlayPanel?
    private var searchVC: SearchViewController?
    private var putVC: PutViewController?
    private var sidecar: SidecarClient!

    // Allow construction from the nonisolated top-level (main.swift). All real
    // setup happens in applicationDidFinishLaunching, which stays main-actor.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu() // enables ⌘C/⌘V/⌘X/⌘A in the text fields (+ ⌘Q)

        sidecar = SidecarClient(binaryURL: resolveSidecarBinary(), dataDir: nil)
        do {
            try sidecar.start()
        } catch {
            NSLog("Butler: failed to launch sidecar: \(error)")
        }

        // Fetch overlay (⌘⌥F)
        let sVC = SearchViewController(sidecar: sidecar)
        sVC.onDismiss = { [weak self] in self?.fetchPanel?.orderOut(nil) }
        fetchPanel = makePanel(vc: sVC, size: NSSize(width: 640, height: 400))
        searchVC = sVC

        // Put overlay (⌘⌥P)
        let pVC = PutViewController(sidecar: sidecar)
        pVC.onDismiss = { [weak self] in self?.putPanel?.orderOut(nil) }
        putPanel = makePanel(vc: pVC, size: NSSize(width: 640, height: 180))
        putVC = pVC

        fetchHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | optionKey)) {
            [weak self] in self?.summonFetch()
        }
        putHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey)) {
            [weak self] in self?.summonPut()
        }
        if fetchHotKey == nil || putHotKey == nil {
            NSLog("Butler: failed to register a global hotkey")
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey(_:)),
            name: NSWindow.didResignKeyNotification, object: nil
        )
    }

    // MARK: - Menu

    // A main menu is required for the standard editing key equivalents (⌘C/⌘V/⌘X/
    // ⌘A) to reach the focused text field's editor. It's never shown (agent app),
    // it just wires up the shortcuts. Also gives ⌘Q to quit.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Butler",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Panels

    private func makePanel(vc: NSViewController, size: NSSize) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentViewController = vc
        return panel
    }

    private func summonFetch() {
        guard let fetchPanel, let searchVC else { return }
        putPanel?.orderOut(nil) // only one overlay at a time
        position(fetchPanel)
        fetchPanel.makeKeyAndOrderFront(nil)
        searchVC.prepareForShow()
    }

    private func summonPut() {
        guard let putPanel, let putVC else { return }
        fetchPanel?.orderOut(nil)
        position(putPanel)
        putPanel.makeKeyAndOrderFront(nil)
        putVC.prepareForShow()
    }

    @objc private func windowResignedKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if window === fetchPanel || window === putPanel { window.orderOut(nil) }
    }

    // Center horizontally, upper third vertically, on whichever screen has the mouse.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY + frame.height * 0.12
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
