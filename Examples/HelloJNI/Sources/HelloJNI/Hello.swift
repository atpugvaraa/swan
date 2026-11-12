import SwiftJavaJNICore

/// Java: `MainActivity.greeting()`.
@_cdecl("Java_swan_hellojni_MainActivity_greeting")
public func greeting(_ env: UnsafeMutablePointer<JNIEnv?>, _ this: jobject?) -> jstring? {
    let sum = (1...10).reduce(0, +)
    return env.pointee!.pointee.NewStringUTF(env, "Hello from Swift. 1 + … + 10 = \(sum)")
}
