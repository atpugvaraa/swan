import Foundation

// `swift android wrap`: Swift wrappers for Java classes, written by swift-java's wrap-java.
//
// The classes a target wraps are listed in Sources/<target>/swift-java.config, swift-java's own
// format. This verb adds to that list and regenerates Sources/<target>/Generated.

/// `android.view.View$OnClickListener` → `View.OnClickListener`
func swiftName(forJavaClass name: String) -> String {
    (name.split(separator: ".").last.map(String.init) ?? name).replacingOccurrences(of: "$", with: ".")
}

/// Runs a command and returns everything it printed, and whether it succeeded.
func capture(_ command: [String]) -> (text: String, succeeded: Bool) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardOutput = pipe
    process.standardError = pipe
    guard (try? process.run()) != nil else { return ("could not run \(command[0])", false) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: data, as: UTF8.self), process.terminationStatus == 0)
}

func wrap(_ arguments: [String]) throws {
    var classpath: [String] = [], classes: [String] = [], target: String?
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        if argument == "--cp" || argument == "--classpath" {
            guard let value = rest.popFirst() else { throw Failure(message: "\(argument) needs a value") }
            classpath.append(value)
        } else if target == nil {
            target = argument
        } else {
            classes.append(argument)
        }
    }
    guard let target else { throw Failure(message: "wrap needs a target name\n\n\(usage)") }
    let fm = FileManager.default
    let directory = "Sources/\(target)"
    guard fm.fileExists(atPath: directory) else { throw Failure(message: "no target at \(directory)") }

    // Add the new classes to the target's list.
    let configPath = "\(directory)/swift-java.config"
    var config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: configPath)))) as? [String: Any] ?? [:]
    var listed = config["classes"] as? [String: String] ?? [:]
    for name in classes where listed[name] == nil { listed[name] = swiftName(forJavaClass: name) }
    guard !listed.isEmpty else { throw Failure(message: "name at least one Java class to wrap, e.g. android.widget.Toast") }
    config["classes"] = listed
    try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        .write(to: URL(fileURLWithPath: configPath))

    // The generator is swift-java's own, built from the version the package resolved.
    let checkout = ".build/checkouts/swift-java"
    if !fm.fileExists(atPath: checkout) { try run([swift, "package", "resolve"], quiet: true) }
    guard fm.fileExists(atPath: checkout) else {
        throw Failure(message: "this package does not depend on swift-java, which the wrappers need")
    }
    print("Building swift-java's generator…")
    let build = [swift, "build", "--package-path", checkout, "--product", "swift-java"]
    try run(build, quiet: true)
    guard let bin = output(build + ["--show-bin-path"]) else { throw Failure(message: "could not find swift-java's build products") }

    if classpath.isEmpty { classpath = [try newest(in: "\(try androidHome())/platforms") + "/android.jar"] }
    let generated = "\(directory)/Generated"
    try? fm.removeItem(atPath: generated)
    let result = capture([
        "\(bin)/swift-java", "wrap-java", "--swift-module", target, "--config", configPath,
        "--cp", classpath.joined(separator: ":"),
        "--depends-on", "SwiftJava=\(checkout)/Sources/SwiftJava/swift-java.config",
        "-o", generated,
    ])
    guard result.succeeded else { throw Failure(message: result.text) }

    // Methods are left out when a type they use is not wrapped. Say which classes would unlock the most.
    var missing: [String: Int] = [:]
    for match in result.text.matches(of: /Java class '([^']+)' has not been translated/) { missing[String(match.1), default: 0] += 1 }
    print("Wrote \(files(under: generated, withExtension: "swift").count) files for \(listed.count) classes to \(generated)")
    let top = missing.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(8)
    if !top.isEmpty {
        print("\(missing.values.reduce(0, +)) methods and fields were skipped. Wrapping these would add the most:")
        for (name, count) in top { print("  \(name)  (\(count))") }
    }
}
