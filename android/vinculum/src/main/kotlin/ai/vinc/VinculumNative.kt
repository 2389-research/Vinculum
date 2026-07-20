package ai.vinc

/**
 * The JNI binding to `libVinculumAndroid.so` (the Swift core + FreeType + C ABI).
 *
 * `renderBytes` returns the raw `VDL1` buffer for [VinculumWire.decode];
 * `setFontDir` points the native side at the extracted `.otf`s (Bundle.module
 * traps inside an APK). Call `setFontDir` once before the first render.
 */
object VinculumNative {
    init {
        System.loadLibrary("VinculumAndroid")   // the Swift core
        System.loadLibrary("vincjni")            // the JNI shim
    }

    /** VDL1 display-list bytes for `latex`, or null if unsupported. */
    external fun renderBytes(latex: String, display: Boolean, baseSize: Double): ByteArray?

    /** Directory holding the bundled `.otf`s (extracted from APK assets). */
    external fun setFontDir(dir: String)

    /** ABI version — refuse a mismatched `.so`. */
    external fun abiVersion(): Int

    /** LaTeX → a decoded display list, or null if unsupported. */
    fun render(latex: String, display: Boolean = true, baseSize: Double = 24.0): VinculumWire.DisplayList? =
        renderBytes(latex, display, baseSize)?.let { VinculumWire.decode(it) }
}
