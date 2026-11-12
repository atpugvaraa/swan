@_exported import SwiftJava

// A first, hand-written slice of the Android API: enough for an Activity that shows text.
// ponytail: written by hand. Generate these from android.jar with swift-java's wrap-java instead.

@JavaClass("android.content.Context")
open class Context: JavaObject {}

@JavaClass("android.os.Bundle")
open class Bundle: JavaObject {}

@JavaClass("android.view.View")
open class View: JavaObject {
    @JavaMethod
    open func setOnClickListener(_ listener: OnClickListener?)

    /// Calls `action` when the view is tapped.
    public func onClick(_ action: @escaping (View?) -> Void) {
        setOnClickListener(.implemented(environment: javaEnvironment) { _, arguments in
            action(arguments.first??.as(View.self))
            return nil
        })
    }
}

@JavaInterface("android.view.View$OnClickListener")
public struct OnClickListener {
    @JavaMethod
    public func onClick(_ view: View?)
}

@JavaClass("android.view.ViewGroup")
open class ViewGroup: View {
    @JavaMethod
    open func addView(_ child: View?)
}

@JavaClass("android.widget.LinearLayout")
open class LinearLayout: ViewGroup {
    @JavaMethod
    @_nonoverride public convenience init(_ context: Context?, environment: JNIEnvironment? = nil)

    /// 0 is horizontal, 1 is vertical.
    @JavaMethod
    open func setOrientation(_ orientation: Int32)
}

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

@JavaClass("android.widget.Button")
open class Button: TextView {
    @JavaMethod
    @_nonoverride public convenience init(_ context: Context?, environment: JNIEnvironment? = nil)
}
