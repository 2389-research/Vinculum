#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// Reduces a `MathScene` to a `DisplayList` — the platform-free emitter behind
/// the Android backend (`docs/ANDROID.md`). Same scene walk as
/// `MathSVGRenderer`, but every element becomes a concrete filled/stroked
/// primitive with its glyphs resolved to outlines, so the result needs no font
/// to draw.
///
/// ```swift
/// let scene = engine.layout(MathParser.parse(latex), display: true)
/// let list  = MathDisplayListRenderer.displayList(for: scene, outliner: myOutliner)
/// // hand `list` across JNI; Kotlin paints it on a Canvas.
/// ```
public enum MathDisplayListRenderer {

    /// The display list for `scene`. `ink` resolves every element that carries
    /// no explicit `\color` (the scene's `nil`); explicit colors win per
    /// element, exactly as every other backend.
    public static func displayList(for scene: MathScene,
                                   outliner: MathOutliner,
                                   ink: MathColor = MathColor(red: 0, green: 0, blue: 0)) -> DisplayList {
        var ops: [DisplayList.Op] = []
        ops.reserveCapacity(scene.elements.count)

        for element in scene.elements {
            switch element {
            case let .glyphs(text, size, mono, origin, color):
                // Shape + pen-advance the run to one outline, then place it at
                // the run's baseline origin.
                let run = outliner.glyphRun(text, size, mono)
                guard !run.isEmpty else { break }
                ops.append(.fillPath(subpaths: run.map { $0.offset(by: origin) },
                                     color: color ?? ink))

            case let .glyph(id, size, origin, color):
                // A MATH-table variant with no character spelling. If the
                // outliner can't produce it, drop it rather than draw a wrong
                // glyph — matches the SVG path's "skip" and keeps the
                // never-half-broken contract (a missing variant is a gap, not a
                // lie). A/B note: this is the case that makes big \left( grow.
                guard let g = outliner.variantGlyph(id, size), !g.isEmpty else { break }
                ops.append(.fillPath(subpaths: g.map { $0.offset(by: origin) },
                                     color: color ?? ink))

            case let .rule(rect, color):
                ops.append(.fillRect(rect, color: color ?? ink))

            case let .stroke(path, width, cap, join, color):
                ops.append(.strokePath(path: path, width: width, cap: cap, join: join,
                                       color: color ?? ink))

            case .region:
                break   // hit-test metadata, not ink
            }
        }

        return DisplayList(width: scene.width, ascent: scene.ascent,
                           descent: scene.descent, ops: ops)
    }
}
