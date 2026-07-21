#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension MathLayoutEngine {

    /// Lays out an inference rule: premises in a centred row above a horizontal
    /// rule, the conclusion centred below it, an optional label beside it. The rule
    /// sits on the math axis (like a fraction bar), so a rule composes into a larger
    /// expression at the right height, and rules nest into proof trees. The bar and
    /// everything else are rules + glyph runs → renders on every platform via VDL1.
    func inferenceRuleBox(premises: [MathNode], conclusion: MathNode, label: MathNode?,
                          size: CGFloat, style: MathStyle) -> MathBox {
        let concl = box(for: conclusion, size: size, style: style)
        let premBoxes = premises.map { box(for: $0, size: size, style: style) }

        let premGap = size * MathLayout.Proof.premiseGap
        let premRowW = premBoxes.reduce(0) { $0 + $1.width } + CGFloat(max(0, premBoxes.count - 1)) * premGap
        let premAsc = premBoxes.map(\.ascent).max() ?? 0
        let premDesc = premBoxes.map(\.descent).max() ?? 0

        let ruleThk = max(0.6, size * constants.defaultRuleThickness)
        let vGap = size * MathLayout.Proof.ruleGap
        let sidePad = size * MathLayout.Proof.sidePad
        let ruleW = max(premRowW, concl.width) + 2 * sidePad

        let axisY = size * constants.axisHeight   // the bar sits on the math axis
        let premBaseline = axisY + ruleThk / 2 + vGap + premDesc
        let conclBaseline = axisY - ruleThk / 2 - vGap - concl.ascent

        let ascent = premBaseline + premAsc
        let descent = max(0, concl.descent - conclBaseline)

        var elements: [MathElement] = []
        // The rule bar.
        elements.append(rule(x: 0, y: axisY - ruleThk / 2, width: ruleW, height: ruleThk))
        // Premises, centred as a row.
        var px = (ruleW - premRowW) / 2
        for b in premBoxes {
            elements += b.placed(at: CGPoint(x: px, y: premBaseline))
            px += b.width + premGap
        }
        // Conclusion, centred.
        elements += concl.placed(at: CGPoint(x: (ruleW - concl.width) / 2, y: conclBaseline))

        var totalW = ruleW
        if let label {
            let lb = box(for: label, size: size * MathLayout.Proof.labelScale, style: .script)
            let lx = ruleW + size * MathLayout.Proof.labelGap
            elements += lb.placed(at: CGPoint(x: lx, y: axisY - (lb.ascent - lb.descent) / 2))
            totalW = lx + lb.width
        }
        return MathBox(width: totalW, ascent: ascent, descent: descent, elements: elements)
    }
}
