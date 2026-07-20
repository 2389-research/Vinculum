package ai.vinc

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Decodes the `VDL1` wire format (Swift `DisplayListWire`) into a drawable
 * display list. The Kotlin counterpart of the Swift serializer — tested against
 * the same committed fixture, so the two ends cannot drift.
 *
 * Coordinates are scene-native: y-up, origin on the baseline. The renderer
 * applies the y-flip once, at draw time.
 */
object VinculumWire {

    /** A concrete drawing primitive: filled outline, filled rect, or stroke. */
    sealed interface Op {
        data class FillPath(val subpaths: List<Seg>, val color: Int) : Op
        data class FillRect(val x: Float, val y: Float, val w: Float, val h: Float, val color: Int) : Op
        data class StrokePath(
            val path: List<Seg>, val width: Float, val cap: Int, val join: Int, val color: Int
        ) : Op
    }

    /** A path segment. `op`: 0 move, 1 line, 2 quad, 3 cubic, 4 close. */
    class Seg(val op: Int, val pts: FloatArray)

    class DisplayList(
        val width: Float, val ascent: Float, val descent: Float, val ops: List<Op>
    ) { val height: Float get() = ascent + descent }

    /** Decodes VDL1 bytes, or null on a bad magic / truncation (never throws). */
    fun decode(bytes: ByteArray): DisplayList? {
        if (bytes.size < 20) return null
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        // magic "VDL1"
        if (b.get() != 'V'.code.toByte() || b.get() != 'D'.code.toByte() ||
            b.get() != 'L'.code.toByte() || b.get() != '1'.code.toByte()) return null
        return try {
            val width = b.float; val ascent = b.float; val descent = b.float
            val opCount = b.int
            if (opCount < 0 || opCount > bytes.size) return null   // untrusted count
            val ops = ArrayList<Op>(minOf(opCount, bytes.size))
            repeat(opCount) {
                when (b.get().toInt()) {
                    0 -> { val c = rgba(b); ops.add(Op.FillPath(readSegs(b), c)) }  // rgba THEN segs
                    1 -> { val c = rgba(b); ops.add(Op.FillRect(b.float, b.float, b.float, b.float, c)) }
                    2 -> {
                        val c = rgba(b); val w = b.float
                        val cap = b.get().toInt(); val join = b.get().toInt()
                        ops.add(Op.StrokePath(readSegs(b), w, cap, join, c))
                    }
                    else -> return null
                }
            }
            DisplayList(width, ascent, descent, ops)
        } catch (_: Exception) { null }
    }

    private fun readSegs(b: ByteBuffer): List<Seg> {
        val n = b.int
        if (n < 0 || n > b.remaining() + 1) throw IllegalStateException("bad segCount")
        val segs = ArrayList<Seg>(minOf(n, b.remaining() + 1))
        repeat(n) {
            when (val op = b.get().toInt()) {
                0, 1 -> segs.add(Seg(op, floatArrayOf(b.float, b.float)))
                2 -> segs.add(Seg(op, floatArrayOf(b.float, b.float, b.float, b.float)))
                3 -> segs.add(Seg(op, floatArrayOf(b.float, b.float, b.float, b.float, b.float, b.float)))
                4 -> segs.add(Seg(op, FloatArray(0)))
                else -> throw IllegalStateException("bad seg op")
            }
        }
        return segs
    }

    /** rgba bytes → an ARGB int for android.graphics.Color. */
    private fun rgba(b: ByteBuffer): Int {
        val r = b.get().toInt() and 0xFF
        val g = b.get().toInt() and 0xFF
        val bl = b.get().toInt() and 0xFF
        val a = b.get().toInt() and 0xFF
        return (a shl 24) or (r shl 16) or (g shl 8) or bl
    }
}
