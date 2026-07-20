package ai.vinc
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import java.io.File
import java.io.FileOutputStream

class DemoActivity : Activity() {
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        try {
            val dir = File(filesDir, "fonts").apply { mkdirs() }
            assets.list("fonts")!!.forEach { n ->
                assets.open("fonts/$n").use { i -> FileOutputStream(File(dir, n)).use { o -> i.copyTo(o) } }
            }
            VinculumNative.setFontDir(dir.absolutePath)
            Log.i("VINCDEMO", "abi=${VinculumNative.abiVersion()}")
            val latex = "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"
            val dl = VinculumNative.render(latex) ?: run { Log.e("VINCDEMO", "render nil"); return }
            Log.i("VINCDEMO", "decoded ops=${dl.ops.size} w=${dl.width} h=${dl.height}")
            val bmp = Bitmap.createBitmap(
                Math.ceil((dl.width + 16).toDouble()).toInt(),
                Math.ceil((dl.height + 16).toDouble()).toInt(),
                Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp); c.drawColor(Color.WHITE)
            SceneRenderer.draw(c, dl, 8f)
            val out = File(getExternalFilesDir(null), "quadratic.png")
            FileOutputStream(out).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            Log.i("VINCDEMO", "WROTE ${out.absolutePath} ${bmp.width}x${bmp.height}")
            Log.i("VINCDEMO", "DONE")
        } catch (t: Throwable) { Log.e("VINCDEMO", "CRASH $t", t) }
    }
}
