import SwiftJava

/// What the code `swift android generate` writes is built on: the link between a Java object
/// made from a Swift subclass and the Swift object behind it.
public enum SwanPeer {
    private static func field(_ this: jobject, _ env: JNIEnvironment) -> jfieldID {
        let jni = env.interface
        let javaClass = jni.GetObjectClass(env, this)
        defer { jni.DeleteLocalRef(env, javaClass) }
        return jni.GetFieldID(env, javaClass, "swanPeer", "J")!
    }

    /// The Swift object behind a Java `this`. Made on first use when Java created the object
    /// (an Activity, say), and kept in its `swanPeer` field so stored properties persist.
    ///
    /// ponytail: the Swift object holds a global reference to the Java object, so neither is
    /// ever freed. Fine for activities and screens; release it from a lifecycle method when it is not.
    public static func resolve<T: AnyJavaObject & AnyObject>(_ type: T.Type, _ this: jobject, _ env: JNIEnvironment) -> T {
        if let existing = UnsafeRawPointer(bitPattern: Int(env.interface.GetLongField(env, this, field(this, env)))) {
            return Unmanaged<T>.fromOpaque(existing).takeUnretainedValue()
        }
        let peer = T(javaThis: this, environment: env)
        adopt(peer, env)
        return peer
    }

    /// Records `peer` as the Swift object for the Java object it wraps.
    public static func adopt<T: AnyJavaObject & AnyObject>(_ peer: T, _ env: JNIEnvironment) {
        let pointer = jlong(Int(bitPattern: Unmanaged.passRetained(peer).toOpaque()))
        env.interface.SetLongField(env, peer.javaThis, field(peer.javaThis, env), pointer)
    }

    /// Makes a Java object of a generated subclass. `signature` is the constructor's JNI signature.
    ///
    /// The class is found through the thread's context class loader: JNI's own FindClass cannot
    /// see an app's or a mod's classes from a thread Java did not call into.
    public static func new(_ className: String, _ signature: String, _ arguments: [jvalue], _ env: JNIEnvironment) -> jobject {
        let jni = env.interface
        let loader = try! JavaClass<JavaThread>(environment: env).currentThread()!.getContextClassLoader()!
        // The wrapper owns the reference to the class, so it has to outlive the calls that use it.
        let type = try! loader.loadClass(className)!
        let object = withExtendedLifetime(type) {
            let constructor = jni.GetMethodID(env, type.javaThis, "<init>", signature)
            return arguments.withUnsafeBufferPointer { jni.NewObjectA(env, type.javaThis, constructor, $0.baseAddress) }
        }
        guard let object, jni.ExceptionCheck(env) == 0 else {
            jni.ExceptionDescribe(env)
            fatalError("could not make a \(className)")
        }
        return object
    }
}
