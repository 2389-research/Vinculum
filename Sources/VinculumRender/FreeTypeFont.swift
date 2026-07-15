// FreeType-backed font for the Linux rendering backend. Loads a bundled MATH
// .otf from bytes (Silica's font-by-name path can't resolve non-default
// families) and provides the two things the renderer needs: glyph metrics for
// the measurer, and glyph outlines (as `PathOp`s) drawn as filled paths.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import CFreetypeShim
import VinculumLayout

final class FreeTypeFont: @unchecked Sendable {
    private var library: FT_Library?
    private var face: FT_Face?
    private let data: Data            // FreeType borrows these bytes; keep them alive.
    let unitsPerEm: CGFloat
    let ascentEm: CGFloat            // font ascender, em-normalized
    let descentEm: CGFloat           // magnitude of the descender, em-normalized

    init?(bytes: Data) {
        self.data = bytes
        var lib: FT_Library?
        guard FT_Init_FreeType(&lib) == 0, let lib else { return nil }
        self.library = lib
        var face: FT_Face?
        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return FT_New_Memory_Face(lib, base, FT_Long(raw.count), 0, &face) == 0
        }
        guard ok, let face else { FT_Done_FreeType(lib); return nil }
        self.face = face
        let upm = CGFloat(face.pointee.units_per_EM)
        self.unitsPerEm = upm > 0 ? upm : 1000
        self.ascentEm = CGFloat(face.pointee.ascender) / self.unitsPerEm
        self.descentEm = abs(CGFloat(face.pointee.descender)) / self.unitsPerEm
    }

    deinit {
        if let face { FT_Done_Face(face) }
        if let library { FT_Done_FreeType(library) }
    }

    /// The glyph index for a Unicode scalar (0 if the font lacks it).
    func glyphIndex(_ scalar: Unicode.Scalar) -> UInt16 {
        guard let face else { return 0 }
        return UInt16(truncatingIfNeeded: FT_Get_Char_Index(face, FT_ULong(scalar.value)))
    }

    /// The glyph's advance width, em-normalized (multiply by point size).
    func advanceEm(glyph: UInt16) -> CGFloat {
        guard let face, FT_Load_Glyph(face, FT_UInt(glyph), FT_Int32(FT_LOAD_NO_SCALE)) == 0,
              let slot = face.pointee.glyph else { return 0 }
        return CGFloat(slot.pointee.advance.x) / unitsPerEm
    }

    /// The glyph's actual ink extents, em-normalized: `top` above the baseline,
    /// `bottom` relative to it (negative below). Accents seat on the real ink,
    /// not the font's global ascent.
    func inkExtentEm(glyph: UInt16) -> (top: CGFloat, bottom: CGFloat) {
        guard let face, FT_Load_Glyph(face, FT_UInt(glyph), FT_Int32(FT_LOAD_NO_SCALE)) == 0,
              let slot = face.pointee.glyph else { return (0, 0) }
        let m = slot.pointee.metrics
        let top = CGFloat(m.horiBearingY) / unitsPerEm
        return (top, top - CGFloat(m.height) / unitsPerEm)
    }

    /// The glyph outline at `size` points, as `PathOp`s in y-up scene
    /// coordinates with the origin at the glyph's baseline pen position.
    func outline(glyph: UInt16, size: CGFloat) -> [PathOp]? {
        guard let face, FT_Load_Glyph(face, FT_UInt(glyph), FT_Int32(FT_LOAD_NO_SCALE)) == 0,
              let slot = face.pointee.glyph else { return nil }
        var outline = slot.pointee.outline
        guard outline.n_points > 0 else { return [] }   // e.g. space

        let acc = OutlineAccumulator(scale: size / unitsPerEm)
        var funcs = FT_Outline_Funcs(
            move_to: { to, user in OutlineAccumulator.of(user).move(to!.pointee); return 0 },
            line_to: { to, user in OutlineAccumulator.of(user).line(to!.pointee); return 0 },
            conic_to: { ctl, to, user in OutlineAccumulator.of(user).conic(ctl!.pointee, to!.pointee); return 0 },
            cubic_to: { c1, c2, to, user in OutlineAccumulator.of(user).cubic(c1!.pointee, c2!.pointee, to!.pointee); return 0 },
            shift: 0, delta: 0)
        let ctx = Unmanaged.passUnretained(acc).toOpaque()
        guard FT_Outline_Decompose(&outline, &funcs, ctx) == 0 else { return nil }
        acc.ops.append(.close)
        return acc.ops
    }
}

/// Collects FreeType decompose callbacks into `PathOp`s, scaling font units to
/// points. FreeType outline coordinates are already y-up (baseline origin),
/// matching the scene.
private final class OutlineAccumulator {
    var ops: [PathOp] = []
    let scale: CGFloat
    private var started = false
    init(scale: CGFloat) { self.scale = scale }

    static func of(_ user: UnsafeMutableRawPointer?) -> OutlineAccumulator {
        Unmanaged<OutlineAccumulator>.fromOpaque(user!).takeUnretainedValue()
    }
    private func p(_ v: FT_Vector) -> CGPoint { CGPoint(x: CGFloat(v.x) * scale, y: CGFloat(v.y) * scale) }

    func move(_ to: FT_Vector) {
        if started { ops.append(.close) }   // close the previous contour
        started = true
        ops.append(.move(p(to)))
    }
    func line(_ to: FT_Vector) { ops.append(.line(p(to))) }
    func conic(_ ctl: FT_Vector, _ to: FT_Vector) { ops.append(.quad(to: p(to), control: p(ctl))) }
    func cubic(_ c1: FT_Vector, _ c2: FT_Vector, _ to: FT_Vector) {
        ops.append(.cubic(to: p(to), control1: p(c1), control2: p(c2)))
    }
}
#endif
