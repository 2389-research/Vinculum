package ai.vinc

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import kotlin.math.ceil

/**
 * Draws a decoded [VinculumWire.DisplayList] onto an Android [Canvas] (B0).
 *
 * The display list carries every glyph already resolved to filled outlines, so
 * this needs no font — just paths, rects, and colors. Scene coordinates are y-up
 * with the origin on the baseline; the single y-flip lives here.
 */
object SceneRenderer {

    /** Renders the display list to a new ARGB bitmap on a transparent ground. */
    fun toBitmap(list: VinculumWire.DisplayList, pad: Float = 4f): Bitmap {
        val w = maxOf(1, ceil(list.width + pad * 2).toInt())
        val h = maxOf(1, ceil(list.height + pad * 2).toInt())
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        draw(Canvas(bmp), list, pad)
        return bmp
    }

    /**
     * Draws into an existing canvas. The caller owns the background (fill it
     * first if opaque is wanted). The origin is placed so the baseline sits
     * `pad + ascent` from the top and scene-y increases upward.
     */
    fun draw(canvas: Canvas, list: VinculumWire.DisplayList, pad: Float = 4f) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.save()
        canvas.translate(pad, pad + list.ascent)   // origin → baseline
        canvas.scale(1f, -1f)                        // scene y-up → canvas y-down
        for (op in list.ops) when (op) {
            is VinculumWire.Op.FillRect -> {
                paint.style = Paint.Style.FILL; paint.color = op.color
                canvas.drawRect(op.x, op.y, op.x + op.w, op.y + op.h, paint)
            }
            is VinculumWire.Op.FillPath -> {
                paint.style = Paint.Style.FILL; paint.color = op.color
                canvas.drawPath(buildPath(op.subpaths), paint)
            }
            is VinculumWire.Op.StrokePath -> {
                paint.style = Paint.Style.STROKE
                paint.color = op.color
                paint.strokeWidth = op.width
                paint.strokeCap = when (op.cap) { 1 -> Paint.Cap.ROUND; 2 -> Paint.Cap.SQUARE; else -> Paint.Cap.BUTT }
                paint.strokeJoin = when (op.join) { 1 -> Paint.Join.ROUND; 2 -> Paint.Join.BEVEL; else -> Paint.Join.MITER }
                canvas.drawPath(buildPath(op.path), paint)
            }
        }
        canvas.restore()
    }

    private fun buildPath(segs: List<VinculumWire.Seg>): Path {
        val p = Path()
        for (s in segs) when (s.op) {
            0 -> p.moveTo(s.pts[0], s.pts[1])
            1 -> p.lineTo(s.pts[0], s.pts[1])
            2 -> p.quadTo(s.pts[2], s.pts[3], s.pts[0], s.pts[1])          // ctrl, then to
            3 -> p.cubicTo(s.pts[2], s.pts[3], s.pts[4], s.pts[5], s.pts[0], s.pts[1])
            4 -> p.close()
        }
        return p
    }
}
