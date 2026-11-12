@_exported import Swan
@_exported import SwiftJava

// What the generated wrappers in Generated/ cannot know: where a Swift String or closure fits.

extension TextView {
    public func setText(_ text: String) {
        setText(JavaString(text, environment: javaEnvironment).as(CharSequence.self))
    }
}

extension View {
    /// Calls `action` when the view is tapped.
    public func onClick(_ action: @escaping (View?) -> Void) {
        setOnClickListener(.implemented(environment: javaEnvironment) { _, arguments in
            action(arguments.first??.as(View.self))
            return nil
        })
    }
}
