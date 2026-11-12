import Foundation

// Subclassing a Java class from Swift.
//
// A JVM only runs an override that exists in a real Java class. So for
//
//     final class MainActivity: Activity {
//         override func onCreate(_ state: Bundle?) { super.onCreate(state) }
//     }
//
// this writes two things:
//
//   MainActivity.java   a real subclass of android.app.Activity. Each override forwards to a native
//                       method. It also keeps the Swift object alive, in a `long` field.
//   SwanSubclasses.swift  the native methods: find the Swift object for `this`, call its override.
//
// `super.onCreate(state)` in Swift is an ordinary virtual JNI call, so it lands on the Java
// override again. The Java override sees that it is already running for that method and calls
// `super` itself, which is what the Swift code meant.

struct JavaSubclass: Equatable {
    struct Method: Equatable {
        var name: String
        var parameters: [String]  // Swift types
        var result: String?  // Swift type, nil for Void
    }
    var name: String
    var superclass: String  // Swift name of the wrapped Java class
    var methods: [Method]
}

/// Swift wrapper name to Java class name, from `@JavaClass("android.app.Activity") open class Activity`.
func javaWrappers(in source: String) -> [String: String] {
    let pattern = /@Java(?:Class|Interface)\(\s*"([^"]+)"[^)]*\)\s*(?:(?:open|public|final)\s+)*(?:class|struct)\s+(\w+)/
    return Dictionary(source.matches(of: pattern).map { (String($0.2), String($0.1)) }, uniquingKeysWith: { first, _ in first })
}

/// The classes in `source` that subclass a wrapped Java class, with the methods they override.
///
/// ponytail: regular expressions, not a Swift parser. Parameters that contain a comma or a
/// parenthesis (closures, tuples, generics with two arguments) are not understood. Use swift-syntax
/// when that matters.
func javaSubclasses(in source: String, wrappers: [String: String]) -> [JavaSubclass] {
    let declaration = /(?:^|\n)[ \t]*(?:(?:public|final|open|internal)\s+)*class\s+(\w+)\s*:\s*(\w+)[^{\n]*\{/
    let override = /override\s+(?:(?:public|open|internal)\s+)*func\s+`?(\w+)`?\s*\(([^)]*)\)\s*(?:->\s*([^{]+?))?\s*\{/
    return source.matches(of: declaration).compactMap { match in
        let (name, superclass) = (String(match.1), String(match.2))
        guard wrappers[name] == nil, wrappers[superclass] != nil else { return nil }
        // The class body runs to the brace that closes the one the declaration opened.
        var depth = 1, end = match.range.upperBound
        while end < source.endIndex, depth > 0 {
            if source[end] == "{" { depth += 1 } else if source[end] == "}" { depth -= 1 }
            end = source.index(after: end)
        }
        let methods = source[match.range.upperBound..<end].matches(of: override).map { method in
            JavaSubclass.Method(
                name: String(method.1),
                parameters: method.2.split(separator: ",").map { parameter in
                    // `_ state: Bundle?` → `Bundle?`
                    parameter.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                },
                result: method.3.map { $0.trimmingCharacters(in: .whitespaces) }
            )
        }
        return JavaSubclass(name: name, superclass: superclass, methods: methods)
    }
}

/// A Swift type as Java source spells it: `Bundle?` → `android.os.Bundle`, `Int32` → `int`.
func javaType(_ swiftType: String, wrappers: [String: String]) throws -> String {
    let primitives = [
        "Bool": "boolean", "Int8": "byte", "Int16": "short", "UInt16": "char", "Int32": "int",
        "Int64": "long", "Float": "float", "Double": "double", "String": "java.lang.String",
    ]
    if let primitive = primitives[swiftType] { return primitive }
    // ponytail: nested types are looked up by their last name (`View.OnClickListener` as
    // `OnClickListener`), so two nested types with one name collide. Track the enclosing type when they do.
    let name = String(swiftType.trimmingCharacters(in: ["?", "!"]).split(separator: ".").last ?? "")
    guard let java = wrappers[name] else {
        throw Failure(message: "cannot pass the Swift type \(swiftType) to Java: no @JavaClass wrapper named \(name) was found")
    }
    return java.replacingOccurrences(of: "$", with: ".")  // nested classes
}

/// A name as it appears in a JNI symbol: `.` separates, and `_` is escaped as `_1`.
func jniEscaped(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: "_1").replacingOccurrences(of: ".", with: "_")
}

func javaStub(_ subclass: JavaSubclass, package: String, library: String, wrappers: [String: String]) throws -> String {
    var body = ""
    for (index, method) in subclass.methods.enumerated() {
        let types = try method.parameters.map { try javaType($0, wrappers: wrappers) }
        let result = try method.result.map { try javaType($0, wrappers: wrappers) } ?? "void"
        let declared = types.enumerated().map { "\($1) a\($0)" }.joined(separator: ", ")
        let passed = types.indices.map { "a\($0)" }.joined(separator: ", ")
        let give = result == "void" ? "" : "return "
        let callSuper = result == "void" ? "super.\(method.name)(\(passed)); return;" : "return super.\(method.name)(\(passed));"
        body += """

                private boolean swanIn\(index);
                private native \(result) swan\(index)(\(declared));

                @Override
                public \(result) \(method.name)(\(declared)) {
                    // Swift's `super.\(method.name)(...)` arrives here while the override is running.
                    if (swanIn\(index)) { \(callSuper) }
                    swanIn\(index) = true;
                    try { \(give)swan\(index)(\(passed)); } finally { swanIn\(index) = false; }
                }

            """
    }
    return """
        // Generated by swift android from the Swift class \(subclass.name). Do not edit.
        package \(package);

        public class \(subclass.name) extends \(try javaType(subclass.superclass, wrappers: wrappers)) {
            static {
                // SwiftJava's JNI_OnLoad only runs when Java loads that library itself.
                try { System.loadLibrary("SwiftJava"); } catch (UnsatisfiedLinkError linkedStatically) {}
                System.loadLibrary("\(library)");
            }

            /// The Swift \(subclass.name), retained. Written by Swift on first use.
            private long swanPeer;
        \(body)}

        """
}

/// `imports`: the import lines of the files the classes are in, so the same type names resolve here.
func swiftThunks(_ subclasses: [JavaSubclass], package: String, imports: [String] = []) -> String {
    // A target with no Java subclasses may not depend on SwiftJava at all.
    if subclasses.isEmpty { return "// Generated by swift android. No Java subclasses in this target.\n" }
    var thunks = ""
    for subclass in subclasses {
        for (index, method) in subclass.methods.enumerated() {
            let symbol = "Java_\(jniEscaped(package))_\(jniEscaped(subclass.name))_swan\(index)"
            let declared = method.parameters.enumerated().map { ", _ a\($0): (\($1)).JNIType" }.joined()
            let passed = method.parameters.enumerated().map { "(\($1))(fromJNI: a\($0), in: env)" }.joined(separator: ", ")
            let call = "swanPeer(\(subclass.name).self, this, env).\(method.name)(\(passed))"
            thunks += """

                @_cdecl("\(symbol)")
                func swan_\(subclass.name)_\(index)(_ env: JNIEnvironment, _ this: jobject\(declared))\(method.result.map { " -> (\($0)).JNIType" } ?? "") {
                    \(method.result == nil ? call : "\(call).getJNIValue(in: env)")
                }

                """
        }
    }
    return """
        // Generated by swift android. Do not edit.
        import SwiftJava
        \(imports.joined(separator: "\n"))
        \(thunks)
        /// The Swift object behind a Java `this`. Made on first use and kept in the Java object's
        /// `swanPeer` field, so stored properties last as long as the Java object is in use.
        ///
        /// ponytail: the Swift object holds a global reference to the Java object, so neither is
        /// ever freed. Fine for activities; release it from a lifecycle method when it is not.
        private func swanPeer<T: AnyJavaObject & AnyObject>(_ type: T.Type, _ this: jobject, _ env: JNIEnvironment) -> T {
            let jni = env.interface
            let javaClass = jni.GetObjectClass(env, this)
            let field = jni.GetFieldID(env, javaClass, "swanPeer", "J")
            jni.DeleteLocalRef(env, javaClass)
            if let existing = UnsafeRawPointer(bitPattern: Int(jni.GetLongField(env, this, field))) {
                return Unmanaged<T>.fromOpaque(existing).takeUnretainedValue()
            }
            let peer = T(javaThis: this, environment: env)
            jni.SetLongField(env, this, field, jlong(Int(bitPattern: Unmanaged.passRetained(peer).toOpaque())))
            return peer
        }

        """
}

/// `swift android generate`: what the build plugin runs for each target.
///
///     generate --module M --library L --output DIR --sources FILE... --wrappers DIR...
///
/// Writes `DIR/SwanSubclasses.swift`, which SwiftPM compiles into the target, and
/// `DIR/swan-java/<package>/<Class>.java`, which `swift android run` compiles into the APK.
func generate(_ arguments: [String]) throws {
    var options: [String: [String]] = [:]
    var key = ""
    for argument in arguments {
        if argument.hasPrefix("--") { key = argument; options[key] = [] } else { options[key, default: []].append(argument) }
    }
    guard let module = options["--module"]?.first, let library = options["--library"]?.first,
          let output = options["--output"]?.first
    else { throw Failure(message: "generate needs --module, --library and --output") }

    let sources = try (options["--sources"] ?? []).map { try String(contentsOfFile: $0, encoding: .utf8) }
    var wrappers: [String: String] = [:]
    for directory in options["--wrappers"] ?? [] {
        for file in files(under: directory, withExtension: "swift") {
            wrappers.merge(javaWrappers(in: try String(contentsOfFile: file, encoding: .utf8))) { first, _ in first }
        }
    }
    for source in sources { wrappers.merge(javaWrappers(in: source)) { first, _ in first } }

    var subclasses: [JavaSubclass] = [], imports: [String] = []
    for source in sources {
        let found = javaSubclasses(in: source, wrappers: wrappers)
        guard !found.isEmpty else { continue }
        subclasses += found
        for line in source.matches(of: /(?:^|\n)[ \t]*((?:@\w+\s+)?import\s+[\w.]+)/) where !imports.contains(String(line.1)) {
            imports.append(String(line.1))
        }
    }
    let package = module.lowercased()
    let java = "\(output)/swan-java/\(package)"
    try? FileManager.default.removeItem(atPath: "\(output)/swan-java")
    try FileManager.default.createDirectory(atPath: java, withIntermediateDirectories: true)
    for subclass in subclasses {
        try javaStub(subclass, package: package, library: library, wrappers: wrappers)
            .write(toFile: "\(java)/\(subclass.name).java", atomically: true, encoding: .utf8)
    }
    try swiftThunks(subclasses, package: package, imports: imports).write(toFile: "\(output)/SwanSubclasses.swift", atomically: true, encoding: .utf8)
}
