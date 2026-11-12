package swan.hellojni;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    static { System.loadLibrary("HelloJNI"); }

    private native String greeting();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView text = new TextView(this);
        text.setTextSize(24);
        text.setText(greeting());
        setContentView(text);
    }
}
