import SwiftJava

// A Swift closure as a Java interface.
//
// Java's own java.lang.reflect.Proxy makes an object that implements any interface and sends
// every call to one handler. The handler is swan.SwanProxy (Java, written next to the generated
// subclasses by SwiftAndroidPlugin), which passes the call to the Swift closure it holds.

@JavaClass("swan.SwanProxy")
open class SwanProxy: JavaObject {}

extension JavaClass<SwanProxy> {
    @JavaStaticMethod
    func make(_ interface: JavaClass<JavaObject>?, _ closure: Int64) -> JavaObject?
}

private final class Closure {
    let body: (String, [JavaObject?]) -> JavaObject?
    init(_ body: @escaping (String, [JavaObject?]) -> JavaObject?) { self.body = body }
}

extension AnyJavaObject {
    /// A Java object that implements this interface by calling `body` with the method's name and
    /// arguments. Return nil from `void` methods, and a boxed value (`JavaBoolean`, …) from
    /// methods that return a primitive.
    ///
    /// The closure is released when Java garbage-collects the object.
    public static func implemented(
        environment: JNIEnvironment? = nil,
        by body: @escaping (_ method: String, _ arguments: [JavaObject?]) -> JavaObject?
    ) -> Self {
        let environment = try! environment ?? JavaVirtualMachine.shared().environment()
        let interface = try! JavaClass<Self>(environment: environment)
        let closure = Int64(Int(bitPattern: Unmanaged.passRetained(Closure(body)).toOpaque()))
        let proxy = try! JavaClass<SwanProxy>(environment: environment)
            .make(JavaClass<JavaObject>(javaHolder: interface.javaHolder), closure)!
        return Self(javaHolder: proxy.javaHolder)
    }
}

/// Java: `SwanProxy.call(closure, method, arguments)`.
@_cdecl("Java_swan_SwanProxy_call")
func swanProxyCall(_ env: JNIEnvironment, _ type: jclass, _ closure: jlong, _ method: jstring?, _ arguments: jobjectArray?) -> jobject? {
    let jni = env.interface
    var objects: [JavaObject?] = []
    if let arguments {
        for index in 0..<jni.GetArrayLength(env, arguments) {
            objects.append(jni.GetObjectArrayElement(env, arguments, index).map { JavaObject(javaThis: $0, environment: env) })
        }
    }
    let body = Unmanaged<Closure>.fromOpaque(UnsafeRawPointer(bitPattern: Int(closure))!).takeUnretainedValue().body
    let result = body(String(fromJNI: method, in: env), objects)
    return result.flatMap { jni.NewLocalRef(env, $0.javaThis) }
}

/// Java: `SwanProxy.release(closure)`, from its finalizer.
@_cdecl("Java_swan_SwanProxy_release")
func swanProxyRelease(_ env: JNIEnvironment, _ type: jclass, _ closure: jlong) {
    Unmanaged<Closure>.fromOpaque(UnsafeRawPointer(bitPattern: Int(closure))!).release()
}
