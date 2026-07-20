package ai.vinc

import java.io.File

/**
 * Cross-language conformance for the `VDL1` wire format (docs/DISPLAYLIST.md).
 *
 * Decodes the committed `Tests/fixtures/displaylist-wire-v1.bin` — the exact bytes
 * the Swift writer produces and that Swift/Linux/macOS/Windows/Android already
 * round-trip — and asserts the Kotlin decoder reconstructs the identical canonical
 * list. This is the twin of Swift `DisplayListWireTests`; together they keep the
 * two ends of the boundary from silently drifting.
 *
 * Pure JVM (`VinculumWire` uses only `java.nio`), so it needs no Android and no
 * emulator. Runnable standalone (`main`, exits non-zero on any failure) and
 * callable from a JUnit wrapper (`check(bytes)` returns the failures) once Gradle
 * lands (see issue P2c).
 */
object VinculumWireConformance {

    private const val EPS = 1e-3f

    /** Returns the list of failures (empty = conformant). */
    fun check(bytes: ByteArray): List<String> {
        val fail = ArrayList<String>()
        fun expect(cond: Boolean, msg: String) { if (!cond) fail.add(msg) }
        fun near(a: Float, b: Float) = kotlin.math.abs(a - b) <= EPS

        val dl = VinculumWire.decode(bytes)
            ?: return listOf("decode returned null on the committed fixture")

        // Header (canonical: width 10, ascent 8, descent 2).
        expect(near(dl.width, 10f), "width ${dl.width} != 10")
        expect(near(dl.ascent, 8f), "ascent ${dl.ascent} != 8")
        expect(near(dl.descent, 2f), "descent ${dl.descent} != 2")
        expect(dl.ops.size == 3, "op count ${dl.ops.size} != 3")
        if (dl.ops.size != 3) return fail   // structural — later checks would index-crash

        // op0: fillRect (1,2,6,0.5), black opaque.
        (dl.ops[0] as? VinculumWire.Op.FillRect)?.let { r ->
            expect(near(r.x, 1f) && near(r.y, 2f) && near(r.w, 6f) && near(r.h, 0.5f),
                "fillRect geom = (${r.x},${r.y},${r.w},${r.h}) != (1,2,6,0.5)")
            expect(r.color == 0xFF000000.toInt(), "fillRect color ${hex(r.color)} != FF000000 (black)")
        } ?: fail.add("op0 is not FillRect")

        // op1: fillPath, red opaque, 5 segments incl. quad/cubic (endpoint-first).
        (dl.ops[1] as? VinculumWire.Op.FillPath)?.let { p ->
            expect(p.color == 0xFFFF0000.toInt(), "fillPath color ${hex(p.color)} != FFFF0000 (red)")
            expect(p.subpaths.size == 5, "fillPath seg count ${p.subpaths.size} != 5")
            if (p.subpaths.size == 5) {
                seg(p.subpaths[0], 0, floatArrayOf(0f, 0f), fail, ::near, "move")
                seg(p.subpaths[1], 1, floatArrayOf(1f, 1f), fail, ::near, "line")
                // quad: endpoint (2,0) then control (1.5,0.5)
                seg(p.subpaths[2], 2, floatArrayOf(2f, 0f, 1.5f, 0.5f), fail, ::near, "quad")
                // cubic: endpoint (3,0), c1 (2.2,0.2), c2 (2.8,-0.2)
                seg(p.subpaths[3], 3, floatArrayOf(3f, 0f, 2.2f, 0.2f, 2.8f, -0.2f), fail, ::near, "cubic")
                seg(p.subpaths[4], 4, floatArrayOf(), fail, ::near, "close")
            }
        } ?: fail.add("op1 is not FillPath")

        // op2: strokePath, width 1.5, cap round(1)/join bevel(2), color 336699.
        (dl.ops[2] as? VinculumWire.Op.StrokePath)?.let { s ->
            expect(near(s.width, 1.5f), "stroke width ${s.width} != 1.5")
            expect(s.cap == 1, "stroke cap ${s.cap} != 1 (round)")
            expect(s.join == 2, "stroke join ${s.join} != 2 (bevel)")
            expect(s.color == 0xFF336699.toInt(), "stroke color ${hex(s.color)} != FF336699")
            expect(s.path.size == 2, "stroke seg count ${s.path.size} != 2")
        } ?: fail.add("op2 is not StrokePath")

        // Robustness: malformed input must return null, never throw.
        expect(VinculumWire.decode(ByteArray(0)) == null, "empty buffer should decode to null")
        expect(VinculumWire.decode("XXXX".toByteArray()) == null, "wrong magic should decode to null")
        expect(VinculumWire.decode(bytes.copyOf(bytes.size - 3)) == null, "truncated tail should decode to null")
        // Forged opCount must not over-allocate or throw (untrusted-count DoS guard).
        val forged = "VDL1".toByteArray() + ByteArray(12) + byteArrayOf(-1, -1, -1, 0x7F)
        expect(VinculumWire.decode(forged) == null, "forged opCount should decode to null, not crash")

        return fail
    }

    private fun seg(
        s: VinculumWire.Seg, op: Int, pts: FloatArray,
        fail: MutableList<String>, near: (Float, Float) -> Boolean, name: String
    ) {
        if (s.op != op) { fail.add("$name: op ${s.op} != $op"); return }
        if (s.pts.size != pts.size) { fail.add("$name: point count ${s.pts.size} != ${pts.size}"); return }
        for (i in pts.indices) if (!near(s.pts[i], pts[i]))
            fail.add("$name: pt[$i] ${s.pts[i]} != ${pts[i]}")
    }

    private fun hex(c: Int) = String.format("%08X", c)

    /** Standalone runner: `... VinculumWireConformanceKt <fixture.bin>`. */
    @JvmStatic
    fun main(args: Array<String>) {
        val path = args.getOrNull(0) ?: "Tests/fixtures/displaylist-wire-v1.bin"
        val f = File(path)
        if (!f.exists()) { System.err.println("FIXTURE NOT FOUND: $path"); kotlin.system.exitProcess(2) }
        val failures = check(f.readBytes())
        if (failures.isEmpty()) {
            println("VDL1 CONFORMANCE: PASS (${f.name}) — Kotlin decoder matches the Swift-written fixture")
        } else {
            println("VDL1 CONFORMANCE: FAIL (${failures.size})")
            failures.forEach { println("  - $it") }
            kotlin.system.exitProcess(1)
        }
    }
}
