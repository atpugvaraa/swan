import Foundation

let usage = """
    USAGE: swift android <verb>

      build [--arch A] [--api N] [swift build options]
          Cross-compile the package in the current directory for Android.

      run [--arch A] [--api N] [swift build options] <product> [arguments]
          Build a product and run it on the attached device or emulator. An executable runs from
          the shell with the arguments. A dynamic library is packaged with the package's Android/
          directory (AndroidManifest.xml, java/, res/) into an APK, installed and launched.
          Build options that take a value must be written --option=value.

      install
          Link this tool into the active toolchain, so `swift android` works.

      --arch   aarch64 | x86_64 | armv7   (default: the attached device's, else aarch64)
      --api    Android API level          (default: 28)
      SWIFT_ANDROID_SDK overrides which installed Swift SDK is used.
    """

struct Failure: Error { let message: String }

// MARK: - Arguments

/// What follows the verb, split into the parts each step needs.
struct Invocation: Equatable {
    var arch: String?
    var api = "28"
    var buildArguments: [String] = []
    var product: String?
    var programArguments: [String] = []

    /// `takesProduct`: the first bare word is the product and everything after it belongs to the program.
    init(_ arguments: [String], takesProduct: Bool) throws {
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--arch", "--api", "-c", "--configuration":
                guard let value = rest.popFirst() else { throw Failure(message: "\(argument) needs a value") }
                switch argument {
                case "--arch": arch = value
                case "--api": api = value
                default: buildArguments += ["-c", value]
                }
            case _ where takesProduct && !argument.hasPrefix("-"):
                product = argument
                programArguments = Array(rest)
                return
            default:
                buildArguments.append(argument)
            }
        }
    }
}

/// `arm64-v8a` (what a device reports) to `aarch64` (what a triple wants).
func arch(forABI abi: String) -> String? {
    ["arm64-v8a": "aarch64", "x86_64": "x86_64", "armeabi-v7a": "armv7"][abi]
}

/// The NDK sysroot directory that holds `libc++_shared.so` for an architecture.
func ndkLibraryDirectory(_ arch: String) -> String {
    arch == "armv7" ? "arm-linux-androideabi" : "\(arch)-linux-android"
}

// MARK: - Processes

/// The `swift` beside this tool when it runs as `swift android`, so the toolchain always matches.
let swift: String = {
    let beside = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("swift").path
    return FileManager.default.isExecutableFile(atPath: beside) ? beside : "swift"
}()

/// Runs a command, inheriting the terminal. A failing child ends this tool with the same status.
/// `quiet` holds the output back and shows it only on failure (adb push reports every file).
func run(_ command: [String], quiet: Bool = false) throws {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    if quiet { process.standardOutput = pipe; process.standardError = pipe }
    try process.run()
    let held = quiet ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        FileHandle.standardError.write(held)
        exit(process.terminationStatus)
    }
}

/// Runs a command and returns its trimmed stdout, or nil if it fails.
func output(_ command: [String]) -> String? {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Swift SDK

/// The installed Swift SDK for Android, e.g. `swift-6.4.2-RELEASE_android`.
func androidSDK() throws -> String {
    if let chosen = ProcessInfo.processInfo.environment["SWIFT_ANDROID_SDK"] { return chosen }
    let installed = output([swift, "sdk", "list"])?.split(separator: "\n").map(String.init) ?? []
    guard let sdk = installed.first(where: { $0.lowercased().contains("android") }) else {
        throw Failure(message: """
            no Swift SDK for Android is installed.
            Install one: https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html
            """)
    }
    return sdk
}

/// A path from the SDK's own configuration (`sdkRootPath`, `swiftResourcesPath`), so nothing is hardcoded.
func sdkPath(_ key: String, sdk: String, triple: String) throws -> String {
    let configuration = output([swift, "sdk", "configure", "--show-configuration", sdk, triple]) ?? ""
    for line in configuration.split(separator: "\n") where line.hasPrefix("\(key): ") {
        return String(line.dropFirst(key.count + 2))
    }
    throw Failure(message: "the Swift SDK \(sdk) has no \(key) for \(triple)")
}

// MARK: - Verbs

func build(_ invocation: Invocation) throws -> (sdk: String, triple: String, swiftBuild: [String]) {
    let sdk = try androidSDK()
    let triple = "\(invocation.arch ?? "aarch64")-unknown-linux-android\(invocation.api)"
    var swiftBuild = [swift, "build", "--swift-sdk", sdk, "--triple", triple] + invocation.buildArguments
    if let product = invocation.product { swiftBuild += ["--product", product] }
    try run(swiftBuild)
    return (sdk, triple, swiftBuild)
}

func runOnDevice(_ parsed: Invocation) throws {
    var invocation = parsed
    guard let product = invocation.product else { throw Failure(message: "run needs a product name\n\n\(usage)") }
    guard output(["adb", "get-state"]) == "device" else {
        throw Failure(message: "no Android device or emulator is attached (adb get-state). Start one: emulator -avd <name>")
    }
    if invocation.arch == nil {
        invocation.arch = output(["adb", "shell", "getprop", "ro.product.cpu.abi"]).flatMap(arch(forABI:))
    }
    let arch = invocation.arch ?? "aarch64"
    let (sdk, triple, swiftBuild) = try build(invocation)

    guard let products = output(swiftBuild + ["--show-bin-path"]) else { throw Failure(message: "could not find the build products") }
    let sysroot = try sdkPath("sdkRootPath", sdk: sdk, triple: triple)
    var libraries = ["\(sysroot)/usr/lib/\(ndkLibraryDirectory(arch))/libc++_shared.so"]
    libraries += sharedLibraries(in: products)

    let isStatic = invocation.buildArguments.contains("--static-swift-stdlib")
    let runtime = isStatic ? [] : sharedLibraries(in: try sdkPath("swiftResourcesPath", sdk: sdk, triple: triple) + "/android")

    // A library product is an app; an executable product runs from the shell.
    if !FileManager.default.fileExists(atPath: "\(products)/\(product)") {
        return try runApp(product: product, abi: abi(forArch: arch), api: invocation.api, libraries: libraries + runtime, products: products)
    }

    let home = "/data/local/tmp/swift-android"
    let directory = "\(home)/\(product)"
    var libraryPath = directory
    try run(["adb", "shell", "mkdir", "-p", directory])
    if !runtime.isEmpty {
        // The Swift runtime is about 110 MB; --sync makes this a one-time cost per SDK and device.
        let shared = "\(home)/runtime-\(sdk)-\(arch)"
        try run(["adb", "shell", "mkdir", "-p", shared])
        try run(["adb", "push", "--sync"] + runtime + [shared], quiet: true)
        libraryPath += ":\(shared)"
    }
    try run(["adb", "push", "--sync", "\(products)/\(product)"] + libraries + [directory], quiet: true)

    let quoted = invocation.programArguments.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    try run(["adb", "shell", (["cd \(directory) && LD_LIBRARY_PATH=\(libraryPath) ./\(product)"] + quoted).joined(separator: " ")])
}

func sharedLibraries(in directory: String) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    return names.filter { $0.hasSuffix(".so") }.sorted().map { "\(directory)/\($0)" }
}

/// Symlinks this executable into the toolchain's usr/bin, the only place `swift` looks for verbs.
func install() throws {
    // <toolchain>/usr/lib/swift, from the compiler itself: works with swiftly, Xcode or a plain install.
    guard let info = output([swift, "-print-target-info"]),
          let json = try? JSONSerialization.jsonObject(with: Data(info.utf8)) as? [String: Any],
          let resources = (json["paths"] as? [String: Any])?["runtimeResourcePath"] as? String,
          let me = Bundle.main.executableURL?.resolvingSymlinksInPath()
    else { throw Failure(message: "could not find the active toolchain") }

    let link = URL(fileURLWithPath: resources).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("bin/swift-android")
    let files = FileManager.default
    if (try? files.destinationOfSymbolicLink(atPath: link.path)) != nil { try files.removeItem(at: link) }
    do { try files.createSymbolicLink(at: link, withDestinationURL: me) } catch {
        throw Failure(message: "could not link \(link.path): \(error.localizedDescription)")
    }
    print("\(link.path) -> \(me.path)\n`swift android` is ready. Undo: rm \(link.path)")
}

@main
enum SwiftAndroid {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            switch arguments.first {
            case "build": _ = try build(Invocation(Array(arguments.dropFirst()), takesProduct: false))
            case "run": try runOnDevice(Invocation(Array(arguments.dropFirst()), takesProduct: true))
            case "install": try install()
            default: print(usage)
            }
        } catch let failure as Failure {
            FileHandle.standardError.write(Data("error: \(failure.message)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}
