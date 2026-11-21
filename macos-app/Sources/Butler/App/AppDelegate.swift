import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fetchHotKey: GlobalHotKey?
    private var putHotKey: GlobalHotKey?
    private var fetch: NotchPresenter?
    private var put: NotchPresenter?
    private var searchVC: SearchViewController?
    private var putVC: PutViewController?
    private var sidecar: SidecarClient!
    private var statusItem: NSStatusItem?
    private var lastSavedHintTask: Task<Void, Never>?

    // Allow construction from the nonisolated top-level (main.swift). All real
    // setup happens in applicationDidFinishLaunching, which stays main-actor.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu() // enables ⌘C/⌘V/⌘X/⌘A in the text fields (+ ⌘Q)
        installStatusItem() // a small menu-bar presence while running

        sidecar = SidecarClient(binaryURL: resolveSidecarBinary(), dataDir: nil)
        sidecar.startWithRetry() // retries with backoff if the binary isn't there yet

        // Both overlays grow out of the notch (see NotchPresenter).
        // Fetch overlay (⌘⌥F)
        let sVC = SearchViewController(sidecar: sidecar)
        sVC.onDismiss = { [weak self] in self?.fetch?.close() }
        fetch = NotchPresenter(host: sVC, contentSize: SearchViewController.contentSize)
        searchVC = sVC

        // Put overlay (⌘⌥P)
        let pVC = PutViewController(sidecar: sidecar)
        pVC.onDismiss = { [weak self] in self?.put?.close() }
        pVC.onSaved = { [weak sVC] in sVC?.refreshRecent() }
        sVC.refreshRecent() // warm the cache so even the first ⌘⌥F fills from memory
        put = NotchPresenter(host: pVC, contentSize: PutViewController.contentSize)
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

    // MARK: - Menu bar

    // A minimal menu-bar icon (SF Symbol, template so it adapts to light/dark)
    // with a click-menu to trigger both overlays and quit. Retained on self so
    // it isn't deallocated (which would remove it from the bar).
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // An emoji title renders in full color (a template SF Symbol is forced to
        // monochrome), so Butler stays easy to spot in a busy menu bar.
        item.button?.title = "📒"
        item.button?.toolTip = "Butler"

        let menu = NSMenu()
        let search = NSMenuItem(title: "Search      ⌘⌥F", action: #selector(menuSearch), keyEquivalent: "")
        search.target = self
        let add = NSMenuItem(title: "Add Note   ⌘⌥P", action: #selector(menuPut), keyEquivalent: "")
        add.target = self
        menu.addItem(search)
        menu.addItem(add)
        menu.addItem(.separator())
        menu.addItem(makeLastNoteReminderMenu())
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Butler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
        startLastSavedHints()
    }

    // MARK: - "Last note" hint

    // Every LastSavedHint.interval, briefly widen the menu-bar item to
    // "📒 last note 3h ago" as a gentle nudge to capture something, then shrink
    // back. Never takes focus or interrupts.
    private func startLastSavedHints() {
        lastSavedHintTask?.cancel()
        let interval = LastSavedHint.interval()
        guard interval > 0 else { return } // reminder turned off
        lastSavedHintTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.showLastSavedHint()
            }
        }
    }

    // "Last-Note Reminder ▸ Off / Every 30 minutes / …", checkmark on the current one.
    private func makeLastNoteReminderMenu() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false // we decide which entries are enabled
        let override = LastSavedHint.environmentOverride()
        if let override {
            // The env var wins over the menu, so say so — and disable the choices
            // (with no tick) rather than show one that isn't in effect.
            let note = NSMenuItem(title: "Overridden: every \(Int(override))s (BUTLER_HINT_INTERVAL)",
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
            submenu.addItem(.separator())
        }
        let current: TimeInterval? = override == nil ? LastSavedHint.interval() : nil
        for (index, choice) in LastSavedHint.choices.enumerated() {
            let entry = NSMenuItem(title: choice.title, action: #selector(selectLastNoteReminder(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.isEnabled = override == nil
            entry.state = choice.seconds == current ? .on : .off
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: "Last-Note Reminder", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func selectLastNoteReminder(_ sender: NSMenuItem) {
        guard LastSavedHint.environmentOverride() == nil else { return } // choices are disabled then anyway
        let choice = LastSavedHint.choices[sender.tag]
        LastSavedHint.setInterval(choice.seconds)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        startLastSavedHints() // apply now: restart the timer at the new interval (or stop it)
    }

    private func showLastSavedHint() async {
        var newest = searchVC?.newestNote
        if newest == nil {
            // Backend unavailable (e.g. restarting)? Skip this hint rather than claim
            // "no notes yet" to someone who has plenty.
            guard let notes = try? await sidecar.fetch("") else { return }
            newest = notes.first
        }
        statusItem?.button?.title = "📒 " + LastSavedHint.text(newestUpdatedAt: newest?.updatedAt)
        try? await Task.sleep(nanoseconds: UInt64(LastSavedHint.visibleFor * 1_000_000_000))
        statusItem?.button?.title = "📒"
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
        let editMenu = EditingShortcuts.makeEditMenu() // same table the panels use
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Panels

    private func summonFetch() {
        guard let fetch, let searchVC else { return }
        let t0 = DispatchTime.now().uptimeNanoseconds
        put?.hideNow() // only one overlay at a time
        fetch.open()
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
        guard let put, let putVC else { return }
        fetch?.hideNow()
        put.open()
        putVC.prepareForShow()
    }

    // Click-away: shrink back into the notch.
    @objc private func windowResignedKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if window === fetch?.panel { fetch?.close() }
        if window === put?.panel { put?.close() }
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
