package com.vinc;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import java.io.*;

/// Minimal JNI smoke harness — the on-device proof (C0c) that Vinculum's Swift
/// core renders LaTeX on real Android. Loads the self-contained
/// libVinculumAndroid.so, extracts the bundled .otf fonts (shipped as APK assets)
/// to filesDir, hands that path to the native lib via setFontDir (Bundle.module
/// traps inside an APK), then calls the C ABI. Verified: renders `x=\frac{-b}{2a}`
/// to a 2681-byte VDL1 display list — byte-identical to the Linux build.
public class MainActivity extends Activity {
    static {
        System.loadLibrary("VinculumAndroid");  // the Swift core + FreeType + C ABI
        System.loadLibrary("smoke");             // the JNI shim (build-freetype-android.sh + a clang -shared)
    }

    public native String render(String latex);   // → "OK abi=1 bytes=N magic=VDL1" or "NIL …"
    public native void setFontDir(String dir);    // vinculum_set_font_dir

    private String extractFonts() throws Exception {
        File dir = new File(getFilesDir(), "fonts");
        dir.mkdirs();
        for (String n : getAssets().list("fonts")) {
            try (InputStream in = getAssets().open("fonts/" + n);
                 OutputStream os = new FileOutputStream(new File(dir, n))) {
                byte[] b = new byte[65536]; int r;
                while ((r = in.read(b)) > 0) os.write(b, 0, r);
            }
        }
        return dir.getAbsolutePath();
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        try {
            setFontDir(extractFonts());
            Log.i("VINCSMOKE", "SUPPORTED " + render("x = \\frac{-b}{2a}"));
            Log.i("VINCSMOKE", "UNSUPPORTED " + render("\\notacommand{x}"));
            Log.i("VINCSMOKE", "DONE");
        } catch (Throwable t) {
            Log.e("VINCSMOKE", "CRASH " + t, t);
        }
    }
}
