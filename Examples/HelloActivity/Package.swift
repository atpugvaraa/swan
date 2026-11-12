// swift-tools-version: 6.1
import PackageDescription

// An Activity written in Swift, with no Java or Kotlin source. Run it: swift android run HelloActivity
let package = Package(
    name: "HelloActivity",
    platforms: [.macOS(.v15)],
    products: [.library(name: "HelloActivity", type: .dynamic, targets: ["HelloActivity"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "HelloActivity",
            dependencies: [.product(name: "AndroidKit", package: "swan")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            plugins: [.plugin(name: "SwiftAndroidPlugin", package: "swan")]
        )
    ]
)
