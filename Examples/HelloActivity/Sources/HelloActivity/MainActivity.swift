import SwanAndroid

final class MainActivity: Activity {
    /// Swift state: it survives between callbacks because the Java object keeps this one alive.
    var taps = 0
    var resumes = 0
    var label: TextView?

    override func onCreate(_ state: Bundle?) {
        super.onCreate(state)

        let label = TextView(self)
        label.setTextSize(24)
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
