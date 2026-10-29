// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LinkRouter",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure routing logic: no AppKit, fully unit-testable.
        .target(name: "RouterCore"),
        // Thin AppKit shell: receives URLs from macOS and launches browsers.
        .executableTarget(name: "LinkRouter", dependencies: ["RouterCore"]),
        .testTarget(name: "RouterCoreTests", dependencies: ["RouterCore"]),
    ]
)
