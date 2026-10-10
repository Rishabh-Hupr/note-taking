import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// .accessory = resident agent: no Dock icon, no menu bar, no default window.
// (For a packaged .app this is also expressed via LSUIElement in Info.plist.)
app.setActivationPolicy(.accessory)
app.run()
