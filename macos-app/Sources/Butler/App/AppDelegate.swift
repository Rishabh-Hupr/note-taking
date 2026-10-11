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
    private var statusItem: NSStatusItem?

    // Allow construction from the nonisolated top-level (main.swift). All real
    // setup happens in applicationDidFinishLaunching, which stays main-actor.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu() // enables ⌘C/⌘V/⌘X/⌘A in the text fields (+ ⌘Q)
        installStatusItem() // a small menu-bar presence while running

        sidecar = SidecarClient(binaryURL: resolveSidecarBinary(), dataDir: nil)
        sidecar.startWithRetry() // retries with backoff if the binary isn't there yet

        // Fetch overlay (⌘⌥F)
        let sVC = SearchViewController(sidecar: sidecar)
        sVC.onDismiss = { [weak self] in self?.fetchPanel?.orderOut(nil) }
        fetchPanel = makePanel(vc: sVC, size: NSSize(width: 640, height: 400))
        searchVC = sVC

        // Put overlay (⌘⌥P)
        let pVC = PutViewController(sidecar: sidecar)
        pVC.onDismiss = { [weak self] in self?.putPanel?.orderOut(nil) }
        putPanel = makePanel(vc: pVC, size: NSSize(width: 640, height: 178))
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
        // Remember where the user drags each overlay so it reopens there.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved(_:)),
            name: NSWindow.didMoveNotification, object: nil
        )
    }

    // MARK: - Menu bar

    // A minimal menu-bar icon (SF Symbol, template so it adapts to light/dark)
    // with a click-menu to trigger both overlays and quit. Retained on self so
    // it isn't deallocated (which would remove it from the bar).
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A butler-ish figure ready to serve; fall back on older macOS.
        let icon = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Butler")
            ?? NSImage(systemSymbolName: "note", accessibilityDescription: "Butler")
        icon?.isTemplate = true
        item.button?.image = icon

        let menu = NSMenu()
        let search = NSMenuItem(title: "Search      ⌘⌥F", action: #selector(menuSearch), keyEquivalent: "")
        search.target = self
        let add = NSMenuItem(title: "Add Note   ⌘⌥P", action: #selector(menuPut), keyEquivalent: "")
        add.target = self
        menu.addItem(search)
        menu.addItem(add)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Butler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @objc private func menuSearch() { summonFetch() }
    @objc private func menuPut() { summonPut() }

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
        let t0 = DispatchTime.now().uptimeNanoseconds
        putPanel?.orderOut(nil) // only one overlay at a time
        position(fetchPanel)
        fetchPanel.makeKeyAndOrderFront(nil)
        let t1 = DispatchTime.now().uptimeNanoseconds
        searchVC.prepareForShow()
        let t2 = DispatchTime.now().uptimeNanoseconds
        // Open-latency breakdown in butler-ui.log. The next main-queue turn runs
        // after this one's display commit, so `firstFrame` ≈ when the filled
        // window was handed to the screen.
        DispatchQueue.main.async {
            let t3 = DispatchTime.now().uptimeNanoseconds
            func ms(_ a: UInt64, _ b: UInt64) -> String { String(format: "%.1fms", Double(b &- a) / 1e6) }
            uiLog("⏱ open show=\(ms(t0, t1)) prepare=\(ms(t1, t2)) firstFrame=\(ms(t2, t3)) total=\(ms(t0, t3))")
        }
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

    // MARK: - Remembered positions

    // True while we move a panel ourselves, so only user drags get saved.
    private var isPositioningPanel = false

    private func originDefaultsKey(for window: NSWindow) -> String? {
        if window === fetchPanel { return "butler.fetchPanelOrigin" }
        if window === putPanel { return "butler.putPanelOrigin" }
        return nil
    }

    @objc private func windowMoved(_ note: Notification) {
        guard !isPositioningPanel,
              let window = note.object as? NSWindow,
              let key = originDefaultsKey(for: window) else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: key)
    }

    // The saved origin, clamped onto the screen it's on — or nil if there's none or
    // that screen is gone (e.g. an unplugged display), so we fall back to default.
    private func savedOrigin(for panel: NSPanel) -> NSPoint? {
        guard let key = originDefaultsKey(for: panel),
              let stored = UserDefaults.standard.string(forKey: key) else { return nil }
        return OverlayLayout.restoredOrigin(
            NSPointFromString(stored), size: panel.frame.size,
            screens: NSScreen.screens.map(\.visibleFrame))
    }

    // Reopen where the user last dragged it; otherwise center horizontally, upper
    // third vertically, on whichever screen has the mouse. Uses visibleFrame and
    // clamps so the panel never clips off-screen or under the menu bar.
    private func position(_ panel: NSPanel) {
        isPositioningPanel = true
        defer { isPositioningPanel = false }
        if let origin = savedOrigin(for: panel) {
            panel.setFrameOrigin(origin)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        panel.setFrameOrigin(OverlayLayout.defaultOrigin(size: panel.frame.size, visible: vf))
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
        // Sibling of this executable — both artifacts are delivered into build/.
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let sibling = exeDir.appendingPathComponent("butler-core")
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
        }
        // Dev fallback: a go-rewrite build next to the working directory.
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd)
            .appendingPathComponent("../go-rewrite/butler-core")
            .standardizedFileURL
    }
}
