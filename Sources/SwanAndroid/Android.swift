@_exported import SwiftJava

// A first, hand-written slice of the Android API: enough for an Activity that shows text.
// ponytail: written by hand. Generate these from android.jar with swift-java's wrap-java instead.

@JavaClass("android.content.Context")
open class Context: JavaObject {}

@JavaClass("android.os.Bundle")
open class Bundle: JavaObject {}

@JavaClass("android.view.View")
open class View: JavaObject {}

@JavaClass("android.widget.TextView")
open class TextView: View {
    @JavaMethod
    @_nonoverride public convenience init(_ context: Context?, environment: JNIEnvironment? = nil)

    @JavaMethod
    open func setText(_ text: CharSequence?)

    @JavaMethod
    open func setTextSize(_ size: Float)

    public func setText(_ text: String) {
        setText(JavaString(text, environment: javaEnvironment).as(CharSequence.self))
    }
}

// Java has ContextThemeWrapper and ContextWrapper in between; JNI only needs the methods to exist.
@JavaClass("android.app.Activity")
open class Activity: Context {
    @JavaMethod
    open func onCreate(_ savedInstanceState: Bundle?)

    @JavaMethod
    open func onResume()

    @JavaMethod
    open func onPause()

    @JavaMethod
    open func setContentView(_ view: View?)
}
