import SwanAndroid

final class MainActivity: Activity {
    /// Swift state: it survives between callbacks because the Java object keeps this one alive.
    var resumes = 0
    var text: TextView?

    override func onCreate(_ state: Bundle?) {
        super.onCreate(state)
        let text = TextView(self)
        text.setTextSize(24)
        text.setText("Hello from a Swift Activity")
        setContentView(text)
        self.text = text
    }

    override func onResume() {
        super.onResume()
        resumes += 1
        text?.setText("Hello from a Swift Activity. Resumed \(resumes)×")
    }
}
