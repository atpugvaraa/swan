// swift-tools-version: 6.1
import PackageDescription

// Java owns the UI and calls a typed Swift API. swift-java's jextract writes the Java bindings;
// swift android compiles them into the APK. Run it: swift android run HelloExtract
let package = Package(
    name: "HelloExtract",
    platforms: [.macOS(.v15)],
    products: [.library(name: "HelloExtract", type: .dynamic, targets: ["HelloExtract"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-java", from: "0.7.0")],
    targets: [
        .target(
            name: "HelloExtract",
            dependencies: [.product(name: "SwiftJava", package: "swift-java")],
            exclude: ["swift-java.config"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            plugins: [.plugin(name: "JExtractSwiftPlugin", package: "swift-java")]
        )
    ]
)
