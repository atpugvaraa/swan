// swift-tools-version: 6.0
import PackageDescription

// Java owns the Activity and calls one Swift function. Run it: swift android run HelloJNI
let package = Package(
    name: "HelloJNI",
    products: [.library(name: "HelloJNI", type: .dynamic, targets: ["HelloJNI"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-java-jni-core", from: "0.5.1")],
    targets: [
        .target(name: "HelloJNI", dependencies: [.product(name: "SwiftJavaJNICore", package: "swift-java-jni-core")])
    ]
)
