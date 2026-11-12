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
//                       Also the initializers, so `MainActivity(...)` in Swift makes the Java
//                       subclass and not the class it inherits from.
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
    /// The superclass's constructors, as Swift parameter types. Java does not inherit constructors,
    /// so the generated subclass repeats each one.
    var constructors: [[String]] = []
}

/// The text between the brace that ends at `start` and the brace that closes it.
func body(of source: String, after start: String.Index) -> Substring {
    var depth = 1, end = start
    while end < source.endIndex, depth > 0 {
        if source[end] == "{" { depth += 1 } else if source[end] == "}" { depth -= 1 }
        end = source.index(after: end)
    }
    return source[start..<end]
}

/// `_ state: Bundle?, environment: JNIEnvironment? = nil` → `["Bundle?"]`
func parameterTypes(_ list: Substring) -> [String] {
    list.split(separator: ",").compactMap { parameter in
        let parts = parameter.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[0].contains("environment") else { return nil }
        return parts[1].split(separator: "=")[0].trimmingCharacters(in: .whitespaces)
    }
}

/// Swift wrapper name to Java class name, from `@JavaClass("android.app.Activity") open class Activity`.
func javaWrappers(in source: String) -> [String: String] {
    let pattern = /@Java(?:Class|Interface)\(\s*"([^"]+)"[^)]*\)\s*(?:(?:open|public|final)\s+)*(?:class|struct)\s+(\w+)/
    return Dictionary(source.matches(of: pattern).map { (String($0.2), String($0.1)) }, uniquingKeysWith: { first, _ in first })
}

/// Swift wrapper name to the constructors it wraps, from its `convenience init(...)` declarations.
func wrapperConstructors(in source: String) -> [String: [[String]]] {
    // Extensions count too: that is where a constructor the generator left out is added by hand.
    let wrapper = /(?:@JavaClass\([^)]*\)\s*(?:(?:open|public|final)\s+)*class|(?:^|\n)[ \t]*(?:public\s+)?extension)\s+(\w+)[^{\n]*\{/
    return Dictionary(source.matches(of: wrapper).map { match in
        (String(match.1), body(of: source, after: match.range.upperBound).matches(of: /convenience\s+init\(([^)]*)\)/).map { parameterTypes($0.1) })
    }, uniquingKeysWith: +)
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
        let methods = body(of: source, after: match.range.upperBound).matches(of: override).map { method in
            JavaSubclass.Method(
                name: String(method.1),
                parameters: parameterTypes(method.2),
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
    return java
}

/// A Swift type as a JNI signature spells it: `Bundle?` → `Landroid/os/Bundle;`, `Int32` → `I`.
func jniDescriptor(_ swiftType: String, wrappers: [String: String]) throws -> String {
    let primitives = ["boolean": "Z", "byte": "B", "short": "S", "char": "C", "int": "I", "long": "J", "float": "F", "double": "D"]
    let java = try javaType(swiftType, wrappers: wrappers)
    return primitives[java] ?? "L\(java.replacingOccurrences(of: ".", with: "/"));"
}

/// A name as it appears in a JNI symbol: `.` separates, and `_` is escaped as `_1`.
func jniEscaped(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: "_1").replacingOccurrences(of: ".", with: "_")
}

func javaStub(_ subclass: JavaSubclass, package: String, library: String, wrappers: [String: String]) throws -> String {
    // `$` separates a nested class in the JVM's name for it; Java source writes a dot.
    let source = { (type: String) in try javaType(type, wrappers: wrappers).replacingOccurrences(of: "$", with: ".") }
    var body = ""
    for constructor in subclass.constructors {
        let declared = try constructor.enumerated().map { "\(try source($1)) a\($0)" }.joined(separator: ", ")
        body += "\n    public \(subclass.name)(\(declared)) { super(\(constructor.indices.map { "a\($0)" }.joined(separator: ", "))); }\n"
    }
    for (index, method) in subclass.methods.enumerated() {
        let types = try method.parameters.map(source)
        let result = try method.result.map(source) ?? "void"
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

        public class \(subclass.name) extends \(try source(subclass.superclass)) {
            static {
                // SwiftJava's JNI_OnLoad only runs when Java loads that library itself.
                try { System.loadLibrary("SwiftJava"); } catch (UnsatisfiedLinkError linkedStatically) {}
                System.loadLibrary("\(library)");
            }

            /// The Swift \(subclass.name), retained. Written by Swift.
            private long swanPeer;
        \(body)}

        """
}

/// `imports`: the import lines of the files the classes are in, so the same type names resolve here.
func swiftThunks(_ subclasses: [JavaSubclass], package: String, imports: [String] = [], wrappers: [String: String] = [:]) throws -> String {
    // A target with no Java subclasses may not depend on SwiftJava at all.
    if subclasses.isEmpty { return "// Generated by swift android. No Java subclasses in this target.\n" }
    var thunks = ""
    for subclass in subclasses {
        for (index, method) in subclass.methods.enumerated() {
            let symbol = "Java_\(jniEscaped(package))_\(jniEscaped(subclass.name))_swan\(index)"
            let declared = method.parameters.enumerated().map { ", _ a\($0): (\($1)).JNIType" }.joined()
            let passed = method.parameters.enumerated().map { "(\($1))(fromJNI: a\($0), in: env)" }.joined(separator: ", ")
            // Backticks, because a Java method may be named like a Swift keyword (Screen.init).
            let call = "SwanPeer.resolve(\(subclass.name).self, this, env).`\(method.name)`(\(passed))"
            thunks += """

                @_cdecl("\(symbol)")
                func swan_\(subclass.name)_\(index)(_ env: JNIEnvironment, _ this: jobject\(declared))\(method.result.map { " -> (\($0)).JNIType" } ?? "") {
                    \(method.result == nil ? call : "\(call).getJNIValue(in: env)")
                }

                """
        }
        // The inherited initializers would make the Java superclass. These make the generated subclass.
        var initializers = ""
        for constructor in subclass.constructors {
            let declared = constructor.enumerated().map { "_ a\($0): \($1), " }.joined()
            let signature = "(\(try constructor.map { try jniDescriptor($0, wrappers: wrappers) }.joined()))V"
            let stored = constructor.enumerated().map {
                "\n        arguments[\($0)][keyPath: (\($1)).jvalueKeyPath] = a\($0).getJNIValue(in: env)"
            }.joined()
            initializers += """

                    @_nonoverride convenience init(\(declared)environment: JNIEnvironment? = nil) {
                        let env = try! environment ?? JavaVirtualMachine.shared().environment()
                        var arguments = [jvalue](repeating: jvalue(), count: \(constructor.count))\(stored)
                        self.init(javaThis: SwanPeer.new("\(package).\(subclass.name)", "\(signature)", arguments, env), environment: env)
                        SwanPeer.adopt(self, env)
                    }

                """
        }
        if !initializers.isEmpty { thunks += "\nextension \(subclass.name) {\(initializers)}\n" }
    }
    return """
        // Generated by swift android. Do not edit.
        import Swan
        import SwiftJava
        \(imports.joined(separator: "\n"))
        \(thunks)
        """
}

/// `swift android generate`: what the build plugin runs for each target.
///
///     generate --module M --library L --output DIR --sources FILE... --wrappers DIR...
///
/// Writes `DIR/SwanSubclasses.swift`, which SwiftPM compiles into the target, and Java sources
/// under `DIR/swan-java`, which `swift android run` (or Gradle, off Android) compiles.
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
    var wrappers: [String: String] = [:], constructors: [String: [[String]]] = [:]
    let wrapperFiles = try (options["--wrappers"] ?? []).flatMap { files(under: $0, withExtension: "swift") }
        .map { try String(contentsOfFile: $0, encoding: .utf8) }
    for source in wrapperFiles + sources {
        wrappers.merge(javaWrappers(in: source)) { first, _ in first }
        constructors.merge(wrapperConstructors(in: source), uniquingKeysWith: +)
    }

    var subclasses: [JavaSubclass] = [], imports: [String] = []
    for source in sources {
        var found = javaSubclasses(in: source, wrappers: wrappers)
        guard !found.isEmpty else { continue }
        for index in found.indices {
            // A constructor that takes a type with no wrapper cannot be called from Swift anyway.
            found[index].constructors = (constructors[found[index].superclass] ?? []).filter { constructor in
                constructor.allSatisfy { (try? javaType($0, wrappers: wrappers)) != nil }
            }
        }
        subclasses += found
        for line in source.matches(of: /(?:^|\n)[ \t]*((?:@\w+\s+)?import\s+[\w.]+)/) where !imports.contains(String(line.1)) {
            imports.append(String(line.1))
        }
    }
    let package = module.lowercased()
    let java = "\(output)/swan-java"
    try? FileManager.default.removeItem(atPath: java)
    try FileManager.default.createDirectory(atPath: "\(java)/\(package)", withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: "\(java)/swan", withIntermediateDirectories: true)
    try swanProxyJava.write(toFile: "\(java)/swan/SwanProxy.java", atomically: true, encoding: .utf8)
    for subclass in subclasses {
        try javaStub(subclass, package: package, library: library, wrappers: wrappers)
            .write(toFile: "\(java)/\(package)/\(subclass.name).java", atomically: true, encoding: .utf8)
    }
    try swiftThunks(subclasses, package: package, imports: imports, wrappers: wrappers)
        .write(toFile: "\(output)/SwanSubclasses.swift", atomically: true, encoding: .utf8)
}

/// The Java half of `AnyJavaObject.implemented(by:)` in the Swan library: one handler class behind
/// every Swift closure that stands in for a Java interface.
let swanProxyJava = """
    package swan;

    import java.lang.reflect.InvocationHandler;
    import java.lang.reflect.Method;
    import java.lang.reflect.Proxy;

    public final class SwanProxy implements InvocationHandler {
        /// The Swift closure, retained until this object is collected.
        private final long closure;

        private SwanProxy(long closure) { this.closure = closure; }

        public static Object make(Class<?> type, long closure) {
            return Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] { type }, new SwanProxy(closure));
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] arguments) {
            if (method.getDeclaringClass() == Object.class) {
                switch (method.getName()) {
                    case "equals": return proxy == arguments[0];
                    case "hashCode": return System.identityHashCode(proxy);
                    default: return "SwanProxy@" + Long.toHexString(closure);
                }
            }
            return call(closure, method.getName(), arguments);
        }

        private static native Object call(long closure, String method, Object[] arguments);
        private static native void release(long closure);

        @Override
        protected void finalize() { release(closure); }
    }

    """
