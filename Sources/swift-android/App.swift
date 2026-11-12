import Foundation

// An app is a package whose product is a dynamic library, with an `Android/` directory beside
// Package.swift:
//
//     Android/AndroidManifest.xml   required
//     Android/java/                 optional Java sources
//     Android/res/                  optional resources
//
// The APK is assembled with the Android SDK's own build tools. There is no Gradle project.

/// The Android SDK: `ANDROID_HOME`, or where Android Studio puts it.
func androidHome() throws -> String {
    let environment = ProcessInfo.processInfo.environment
    let home = environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"] ?? NSHomeDirectory() + "/Library/Android/sdk"
    guard FileManager.default.fileExists(atPath: home) else {
        throw Failure(message: "no Android SDK at \(home). Set ANDROID_HOME.")
    }
    return home
}

/// The highest-numbered entry of a versioned SDK directory, e.g. `build-tools/37.0.0`.
func newest(in directory: String) throws -> String {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    guard let name = names.filter({ !$0.hasPrefix(".") }).max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else {
        throw Failure(message: "\(directory) is empty. Install it with Android Studio's SDK Manager.")
    }
    return "\(directory)/\(name)"
}

func files(under directory: String, withExtension ext: String) -> [String] {
    guard let walker = FileManager.default.enumerator(atPath: directory) else { return [] }
    return walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".\(ext)") }.sorted().map { "\(directory)/\($0)" }
}

/// Builds `<product>.apk` from the built libraries and the package's `Android/` directory, then
/// installs and launches it.
func runApp(product: String, abi: String, api: String, libraries: [String], products: String) throws {
    let fm = FileManager.default
    let source = fm.currentDirectoryPath + "/Android"
    let manifest = "\(source)/AndroidManifest.xml"
    guard fm.fileExists(atPath: manifest) else {
        throw Failure(message: "\(product) is a library, so it runs as an app, and an app needs Android/AndroidManifest.xml")
    }
    let home = try androidHome()
    let tools = try newest(in: "\(home)/build-tools")
    let androidJar = try newest(in: "\(home)/platforms") + "/android.jar"

    // Everything is staged under the build directory, laid out as it will be inside the APK.
    let stage = "\(products)/\(product).apk-stage"
    let apk = "\(products)/\(product).apk"
    try? fm.removeItem(atPath: stage)
    try fm.createDirectory(atPath: "\(stage)/lib/\(abi)", withIntermediateDirectories: true)
    for library in libraries {
        try fm.copyItem(atPath: library, toPath: "\(stage)/lib/\(abi)/\((library as NSString).lastPathComponent)")
    }

    // Java sources: javac to .class, d8 to classes.dex.
    var contents = ["lib"]
    let java = files(under: "\(source)/java", withExtension: "java")
    if !java.isEmpty {
        try run(["javac", "--release", "17", "-Xlint:-options", "-classpath", androidJar, "-d", "\(stage)/classes"] + java)
        try run(["\(tools)/d8", "--lib", androidJar, "--min-api", api, "--output", stage]
            + files(under: "\(stage)/classes", withExtension: "class"))
        contents.append("classes.dex")
    }

    // Manifest and resources: aapt2 writes the APK, then the libraries and dex are zipped into it.
    var link = ["\(tools)/aapt2", "link", "-o", "\(stage)/unaligned.apk", "--manifest", manifest, "-I", androidJar,
                "--min-sdk-version", api, "--target-sdk-version", api]
    if fm.fileExists(atPath: "\(source)/res") {
        try run(["\(tools)/aapt2", "compile", "--dir", "\(source)/res", "-o", "\(stage)/res.zip"])
        link.append("\(stage)/res.zip")
    }
    try run(link)
    // ponytail: stored, not compressed (-0): a debug APK that builds fast. Compress for release when there is one.
    try run(["sh", "-c", "cd '\(stage)' && zip -q -r -0 unaligned.apk \(contents.joined(separator: " "))"])
    try run(["\(tools)/zipalign", "-f", "-P", "16", "4", "\(stage)/unaligned.apk", apk])

    // The debug keystore is the one Android Studio and Gradle already use; its password is public.
    let keystore = NSHomeDirectory() + "/.android/debug.keystore"
    if !fm.fileExists(atPath: keystore) {
        try fm.createDirectory(atPath: NSHomeDirectory() + "/.android", withIntermediateDirectories: true)
        try run(["keytool", "-genkeypair", "-keystore", keystore, "-storepass", "android", "-keypass", "android",
                 "-alias", "androiddebugkey", "-dname", "CN=Android Debug,O=Android,C=US", "-keyalg", "RSA", "-validity", "10000"],
                quiet: true)
    }
    try run(["\(tools)/apksigner", "sign", "--ks", keystore, "--ks-pass", "pass:android", apk])

    guard let package = output(["\(tools)/aapt2", "dump", "packagename", apk]) else {
        throw Failure(message: "could not read the package name from \(manifest)")
    }
    try run(["adb", "install", "-r", apk], quiet: true)
    // Starts whichever activity the manifest marks as the launcher.
    try run(["adb", "shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"], quiet: true)
    print("\(apk)\nLaunched \(package). Logs: adb logcat --pid=$(adb shell pidof \(package))")
}

/// `aarch64` (what a triple wants) to `arm64-v8a` (the directory an APK wants).
func abi(forArch arch: String) -> String {
    ["aarch64": "arm64-v8a", "armv7": "armeabi-v7a"][arch] ?? arch
}
