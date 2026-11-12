import AndroidKit

final class MainActivity: Activity {
    /// Swift state: it survives between callbacks because the Java object keeps this one alive.
    var taps = 0
    var resumes = 0
    var label: TextView?

    override func onCreate(_ state: Bundle?) {
        super.onCreate(state)

        let label = CounterLabel(self)
        self.label = label

        let button = Button(self)
        button.setText("Tap")
        button.onClick { [unowned self] _ in
            taps += 1
            update()
        }

        let column = LinearLayout(self)
        column.setOrientation(1)
        column.addView(label)
        column.addView(button)
        setContentView(column)
    }

    override func onResume() {
        super.onResume()
        resumes += 1
        update()
    }

    func update() {
        label?.setText("Hello from a Swift Activity.\nTaps: \(taps). Resumed \(resumes)×")
    }
}

/// A Swift subclass that Swift itself creates: `CounterLabel(context)` makes the generated Java
/// subclass, so Android calls the override below.
final class CounterLabel: TextView {
    var attached = 0

    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        attached += 1
        setTextSize(24)
        setText("attached \(attached)×, waiting for onResume")
    }
}
