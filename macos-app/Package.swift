// swift-tools-version:5.9
import PackageDescription

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
        )
    ]
)
