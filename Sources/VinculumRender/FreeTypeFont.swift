// FreeType-backed font for the Linux rendering backend. Loads a bundled MATH
// .otf from bytes (Silica's font-by-name path can't resolve non-default
// families) and provides the two things the renderer needs: glyph metrics for
// the measurer, and glyph outlines (as `PathOp`s) drawn as filled paths.
#if canImport(CFreetypeShim) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import CFreetypeShim
import VinculumLayout

final class FreeTypeFont: @unchecked Sendable {
    private var library: FT_Library?
    private var face: FT_Face?
    /// The font bytes, owned outright.
    ///
    /// `FT_New_Memory_Face` does **not** copy: it reads through this pointer on
    /// every later `FT_Load_Glyph`, i.e. for the face's whole lifetime. But
    /// `Data.withUnsafeBytes` only guarantees its pointer *for the duration of
    /// the closure* — nothing forbids `Data` from vending a temporary and keeping
    /// its bytes elsewhere. Holding the `Data` alive kept the buffer alive but
    /// never promised FreeType's stored address stayed valid, so correctness
    /// rested on `Data`'s undocumented representation. Own the buffer instead and
    /// the guarantee is ours to make (#4).
    private let storage: UnsafeMutableBufferPointer<UInt8>

    /// Serializes every use of `face`.
    ///
    /// FreeType allows only one thread at a time per `FT_Face`, and each accessor
    /// below calls `FT_Load_Glyph`, which mutates the face's *shared* glyph slot —
    /// so two concurrent `advanceEm` calls race inside libfreetype. Without this,
    /// the `@unchecked Sendable` above is a promise the type doesn't keep. Mirrors
    /// `MathFont.ctFontLock`, which backs the same annotation on Apple (#3).
    private let lock = NSLock()

    let unitsPerEm: CGFloat
    let ascentEm: CGFloat            // font ascender, em-normalized
    let descentEm: CGFloat           // magnitude of the descender, em-normalized

    init?(bytes: Data) {
        // Stable, self-owned copy — see `storage`. Freed in deinit, and on every
        // failure path below (a failable class init that returns nil before full
        // initialization never runs deinit, so cleanup here is manual).
        let storage = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bytes.count)
        _ = storage.initialize(fromContentsOf: bytes)

        var lib: FT_Library?
        guard FT_Init_FreeType(&lib) == 0, let lib else {
            storage.deallocate(); return nil
        }
        var face: FT_Face?
        guard FT_New_Memory_Face(lib, storage.baseAddress, FT_Long(storage.count), 0, &face) == 0,
              let face else {
            FT_Done_FreeType(lib); storage.deallocate(); return nil
        }
        self.storage = storage
        self.library = lib
        self.face = face
        let upm = CGFloat(face.pointee.units_per_EM)
        self.unitsPerEm = upm > 0 ? upm : 1000
        self.ascentEm = CGFloat(face.pointee.ascender) / self.unitsPerEm
        self.descentEm = abs(CGFloat(face.pointee.descender)) / self.unitsPerEm
    }

    deinit {
        // Free the buffer last: FreeType holds a pointer into `storage` for the
        // face's lifetime, so tearing the face down first is the conservative
        // order. (Reversing it doesn't trip ASan today — FT_Done_Face appears not
        // to read the buffer — but that's an implementation detail of FreeType,
        // not a guarantee, and not one worth depending on.)
        if let face { FT_Done_Face(face) }
        if let library { FT_Done_FreeType(library) }
        storage.deallocate()
    }

    /// The OpenType `'MATH'` sfnt table tag.
    static let mathTableTag: UInt32 = 0x4D41_5448

    /// The raw bytes of an sfnt table (e.g. `'MATH'`), or nil if the font has no
    /// such table.
    ///
    /// `MathTableParser` parses a TABLE, never a font file: the Apple path feeds
    /// it `CGFont.table(for: 'MATH')`, and this is the FreeType counterpart.
    /// Handing it a whole `.otf` instead fails the table's version guard — the
    /// bytes there are the sfnt tag — which is how every bundled font silently
    /// fell back to Latin Modern's metrics on Linux (#1).
    func sfntTable(tag: UInt32) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let face else { return nil }
        // Two-pass, per FreeType's API: a nil buffer reports the length.
        var length: FT_ULong = 0
        guard FT_Load_Sfnt_Table(face, FT_ULong(tag), 0, nil, &length) == 0, length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(length))
        let ok = bytes.withUnsafeMutableBufferPointer { buf -> Bool in
            FT_Load_Sfnt_Table(face, FT_ULong(tag), 0, buf.baseAddress, &length) == 0
        }
        return ok ? Data(bytes) : nil
    }

    /// The glyph index for a Unicode scalar (0 if the font lacks it).
    func glyphIndex(_ scalar: Unicode.Scalar) -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        guard let face else { return 0 }
        return UInt16(truncatingIfNeeded: FT_Get_Char_Index(face, FT_ULong(scalar.value)))
    }

    /// The glyph's advance width, em-normalized (multiply by point size).
    func advanceEm(glyph: UInt16) -> CGFloat {
        lock.lock(); defer { lock.unlock() }
        guard let face, FT_Load_Glyph(face, FT_UInt(glyph), FT_Int32(FT_LOAD_NO_SCALE)) == 0,
              let slot = face.pointee.glyph else { return 0 }
        return CGFloat(slot.pointee.advance.x) / unitsPerEm
    }

    /// The glyph's actual ink extents, em-normalized: `top` above the baseline,
    /// `bottom` relative to it (negative below). Accents seat on the real ink,
    /// not the font's global ascent.
    func inkExtentEm(glyph: UInt16) -> (top: CGFloat, bottom: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        guard let face, FT_Load_Glyph(face, FT_UInt(glyph), FT_Int32(FT_LOAD_NO_SCALE)) == 0,
              let slot = face.pointee.glyph else { return (0, 0) }
        let m = slot.pointee.metrics
        let top = CGFloat(m.horiBearingY) / unitsPerEm
        return (top, top - CGFloat(m.height) / unitsPerEm)
    }

    /// The glyph outline at `size` points, as `PathOp`s in y-up scene
    /// coordinates with the origin at the glyph's baseline pen position.
    func outline(glyph: UInt16, size: CGFloat) -> [PathOp]? {
        // Held across the decompose too: it reads the slot FT_Load_Glyph just filled.
        lock.lock(); defer { lock.unlock() }
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
