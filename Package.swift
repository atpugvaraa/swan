// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swan",
    platforms: [.macOS(.v13)],
    products: [
        // The `swift` driver runs `swift-<word>` from the toolchain's usr/bin, so this name is the verb.
        .executable(name: "swift-android", targets: ["swift-android"])
    ],
    targets: [
        .executableTarget(name: "swift-android"),
        .testTarget(name: "SwanTests", dependencies: ["swift-android"]),
    ]
)
