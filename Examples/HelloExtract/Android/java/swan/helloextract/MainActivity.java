package swan.helloextract;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
import org.swift.swiftkit.core.SwiftArena;
import swan.helloextract.swift.HelloExtract;
import swan.helloextract.swift.Track;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String message;
        try (var arena = SwiftArena.ofConfined()) {
            Track first = Track.init("Around the World", 429, arena);
            Track second = Track.init("One More Time", 320, arena);
            message = "Longest: " + HelloExtract.longest(first, second, arena).describe()
                + "\nfibonacci(20) = " + HelloExtract.fibonacci(20);
        }
        TextView text = new TextView(this);
        text.setTextSize(22);
        text.setText(message);
        setContentView(text);
    }
}
