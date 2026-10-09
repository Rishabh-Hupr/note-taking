// swift-tools-version:5.9
import Foundation
import PackageDescription

// The Swift Testing macros (@Test, #expect) are a compiler plugin. With Command
// Line Tools, SwiftPM intermittently omits the plugin path on incremental builds
// ("plugin for module 'TestingMacros' not found"), so pass it explicitly — found
// under whichever toolchain is active (Command Line Tools or Xcode).
let testingPluginDir: String? = [
    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing",
].first { FileManager.default.fileExists(atPath: $0) }

let package = Package(
    name: "Butler",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure AppKit executable, no external dependencies. The global hotkey is
        // implemented directly against Carbon (built into macOS), so `swift build`
        // needs no network fetch.
        .executableTarget(
            name: "Butler",
            path: "Sources/Butler"
        ),
        // Swift Testing (XCTest isn't available with Command Line Tools alone).
        .testTarget(
            name: "ButlerTests",
            dependencies: ["Butler"],
            swiftSettings: testingPluginDir.map { [.unsafeFlags(["-plugin-path", $0])] } ?? []
        ),
    ]
)
