// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swan",
    platforms: [.macOS(.v15)],
    products: [
        // The `swift` driver runs `swift-<word>` from the toolchain's usr/bin, so this name is the verb.
        .executable(name: "swift-android", targets: ["swift-android"]),
        // Add to a target's `plugins:` to subclass Java classes in Swift.
        .plugin(name: "SwanPlugin", targets: ["SwanPlugin"]),
        // What generated code calls into. Every target that uses SwanPlugin depends on it.
        .library(name: "Swan", targets: ["Swan"]),
        // Swan plus wrappers for the Android API.
        .library(name: "SwanAndroid", targets: ["SwanAndroid"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-java", from: "0.4.1")
    ],
    targets: [
        .executableTarget(name: "swift-android"),
        .testTarget(name: "SwanTests", dependencies: ["swift-android"]),
        .plugin(name: "SwanPlugin", capability: .buildTool(), dependencies: ["swift-android"]),
        .target(
            name: "Swan",
            dependencies: [.product(name: "SwiftJava", package: "swift-java")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "SwanAndroid",
            dependencies: ["Swan", .product(name: "SwiftJava", package: "swift-java")],
            exclude: ["swift-java.config"],  // the classes `swift android wrap SwanAndroid` generates
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
