#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The wire format that carries a `DisplayList` across the JNI boundary to the
/// Android `Canvas` side (`docs/ANDROID.md`, #78).
///
/// A hand-rolled, little-endian tagged binary — **not** FlatBuffers. The package
/// is dependency-free by charter (`Package.swift`), FlatBuffers needs a runtime
/// dependency *and* a `flatc` codegen step, and a display list is a few KB where
/// zero-copy buys nothing measurable. This format is a few dozen lines to write
/// here and to read in Kotlin (`ByteBuffer.order(LITTLE_ENDIAN)`), with no tools.
///
/// ## Layout (all integers/floats little-endian)
/// ```
/// magic    : 4 bytes  "VDL1"            // the "1" is the version; a break bumps to "VDL2"
/// width    : f32
/// ascent   : f32
/// descent  : f32
/// opCount  : u32
/// ops      : opCount × Op
///
/// Op:
///   tag : u8
///     0 fillPath   : rgba(4×u8), segCount(u32), Seg × segCount
///     1 fillRect   : rgba(4×u8), x,y,w,h (4×f32)
///     2 strokePath : rgba(4×u8), width(f32), cap(u8), join(u8), segCount(u32), Seg × segCount
///
/// Seg:
///   op : u8
///     0 move  : x,y (2×f32)
///     1 line  : x,y (2×f32)
///     2 quad  : tx,ty, cx,cy (4×f32)
///     3 cubic : tx,ty, c1x,c1y, c2x,c2y (6×f32)
///     4 close : —
/// ```
/// Colors are 8-bit rgba (the Canvas draws in 8-bit anyway). Coordinates are f32
/// (the Canvas draws in float) and stay scene-native (y-up, baseline origin); the
/// y-down flip and padding happen once on the consumer side.
///
/// Versioning: readers MUST check the 4-byte magic and reject an unknown one. A
/// backward-compatible addition (a new trailing field on an existing op, or a new
/// op tag a reader can skip) can keep "VDL1"; any change that would mislead an old
/// reader bumps the magic.
public enum DisplayListWire {

    public static let magic: [UInt8] = Array("VDL1".utf8)

    // MARK: - Write

    public static func serialize(_ list: DisplayList) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(64 + list.ops.count * 32)
        out += magic
        putF32(&out, list.width); putF32(&out, list.ascent); putF32(&out, list.descent)
        putU32(&out, UInt32(list.ops.count))
        for op in list.ops {
            switch op {
            case let .fillPath(subpaths, color):
                out.append(0); putRGBA(&out, color); putSegs(&out, subpaths)
            case let .fillRect(rect, color):
                out.append(1); putRGBA(&out, color)
                putF32(&out, rect.origin.x); putF32(&out, rect.origin.y)
                putF32(&out, rect.size.width); putF32(&out, rect.size.height)
            case let .strokePath(path, width, cap, join, color):
                out.append(2); putRGBA(&out, color)
                putF32(&out, width); out.append(capCode(cap)); out.append(joinCode(join))
                putSegs(&out, path)
            }
        }
        return out
    }

    private static func putSegs(_ out: inout [UInt8], _ path: [PathOp]) {
        putU32(&out, UInt32(path.count))
        for seg in path {
            switch seg {
            case let .move(p):  out.append(0); putF32(&out, p.x); putF32(&out, p.y)
            case let .line(p):  out.append(1); putF32(&out, p.x); putF32(&out, p.y)
            case let .quad(t, c):
                out.append(2); putF32(&out, t.x); putF32(&out, t.y); putF32(&out, c.x); putF32(&out, c.y)
            case let .cubic(t, c1, c2):
                out.append(3)
                putF32(&out, t.x); putF32(&out, t.y)
                putF32(&out, c1.x); putF32(&out, c1.y); putF32(&out, c2.x); putF32(&out, c2.y)
            case .close: out.append(4)
            }
        }
    }

    private static func putU32(_ out: inout [UInt8], _ v: UInt32) {
        let le = v.littleEndian
        out.append(UInt8(le & 0xFF)); out.append(UInt8((le >> 8) & 0xFF))
        out.append(UInt8((le >> 16) & 0xFF)); out.append(UInt8((le >> 24) & 0xFF))
    }
    private static func putF32(_ out: inout [UInt8], _ v: CGFloat) {
        putU32(&out, Float(v).bitPattern)
    }
    private static func putRGBA(_ out: inout [UInt8], _ c: MathColor) {
        func b(_ v: CGFloat) -> UInt8 { UInt8((max(0, min(1, v)) * 255).rounded()) }
        out.append(b(c.red)); out.append(b(c.green)); out.append(b(c.blue)); out.append(b(c.alpha))
    }
    private static func capCode(_ c: StrokeCap) -> UInt8 { switch c { case .butt: 0; case .round: 1; case .square: 2 } }
    private static func joinCode(_ j: StrokeJoin) -> UInt8 { switch j { case .miter: 0; case .round: 1; case .bevel: 2 } }

    // MARK: - Read (reference decoder; the shipping reader is Kotlin)

    /// Decodes a buffer produced by `serialize`, or nil if it is truncated or
    /// carries an unknown magic — never traps. The reference the Kotlin reader is
    /// tested against.
    public static func deserialize(_ bytes: [UInt8]) -> DisplayList? {
        var r = Reader(bytes)
        guard r.take(4) == magic,
              let width = r.f32(), let ascent = r.f32(), let descent = r.f32(),
              let opCount = r.u32() else { return nil }
        var ops: [DisplayList.Op] = []
        // Cap the reserve to bytes actually present: opCount comes from an
        // untrusted buffer (the JNI boundary), and each op is ≥ 1 byte, so a
        // count larger than what's left is a lie. Reserving on the raw count let
        // a forged opCount request a 154 GB allocation and crash the process —
        // a DoS from the boundary. The loop's per-field guards still return nil
        // on the real truncation.
        ops.reserveCapacity(min(Int(opCount), r.remaining))
        for _ in 0..<opCount {
            guard let tag = r.u8() else { return nil }
            switch tag {
            case 0:
                guard let color = r.rgba(), let segs = r.segs() else { return nil }
                ops.append(.fillPath(subpaths: segs, color: color))
            case 1:
                guard let color = r.rgba(), let x = r.f32(), let y = r.f32(),
                      let w = r.f32(), let h = r.f32() else { return nil }
                ops.append(.fillRect(CGRect(origin: CGPoint(x: x, y: y),
                                            size: CGSize(width: w, height: h)), color: color))
            case 2:
                guard let color = r.rgba(), let width = r.f32(),
                      let cap = r.u8(), let join = r.u8(), let segs = r.segs() else { return nil }
                ops.append(.strokePath(path: segs, width: width,
                                       cap: cap == 1 ? .round : cap == 2 ? .square : .butt,
                                       join: join == 1 ? .round : join == 2 ? .bevel : .miter,
                                       color: color))
            default:
                return nil   // unknown op tag: a "VDL1" reader can't skip it safely
            }
        }
        return DisplayList(width: width, ascent: ascent, descent: descent, ops: ops)
    }

    private struct Reader {
        let b: [UInt8]; var i = 0
        init(_ bytes: [UInt8]) { b = bytes }
        var remaining: Int { b.count - i }
        mutating func take(_ n: Int) -> [UInt8]? {
            guard i + n <= b.count else { return nil }
            defer { i += n }; return Array(b[i..<i + n])
        }
        mutating func u8() -> UInt8? { guard i < b.count else { return nil }; defer { i += 1 }; return b[i] }
        mutating func u32() -> UInt32? {
            guard i + 4 <= b.count else { return nil }; defer { i += 4 }
            return UInt32(b[i]) | UInt32(b[i+1]) << 8 | UInt32(b[i+2]) << 16 | UInt32(b[i+3]) << 24
        }
        mutating func f32() -> CGFloat? { u32().map { CGFloat(Float(bitPattern: $0)) } }
        mutating func rgba() -> MathColor? {
            guard let c = take(4) else { return nil }
            return MathColor(red: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255,
                             blue: CGFloat(c[2]) / 255, alpha: CGFloat(c[3]) / 255)
        }
        mutating func point() -> CGPoint? {
            guard let x = f32(), let y = f32() else { return nil }; return CGPoint(x: x, y: y)
        }
        mutating func segs() -> [PathOp]? {
            guard let n = u32() else { return nil }
            var out: [PathOp] = []; out.reserveCapacity(min(Int(n), remaining))   // untrusted count — see deserialize
            for _ in 0..<n {
                guard let op = u8() else { return nil }
                switch op {
                case 0: guard let p = point() else { return nil }; out.append(.move(p))
                case 1: guard let p = point() else { return nil }; out.append(.line(p))
                case 2: guard let t = point(), let c = point() else { return nil }; out.append(.quad(to: t, control: c))
                case 3:
                    guard let t = point(), let c1 = point(), let c2 = point() else { return nil }
                    out.append(.cubic(to: t, control1: c1, control2: c2))
                case 4: out.append(.close)
                default: return nil
                }
            }
            return out
        }
    }
}
