# Review refutations — the findings that didn't survive
A July-2026 multi-expert review produced 67 raw findings, deduped to 52
candidates. Each was then handed to an adversarial validator that re-read the
actual code before anything was filed. 47 survived and became issues #1–#47. **5
were refuted** — recorded here, because they are the most interesting output:
they are what a panel of confident experts gets *wrong*, and the reason the
surviving list is worth trusting.

Filing all 52 would have been worse than filing none — it would have burned
trust in the list. Each verdict below is the validator's own reasoning.

---

## SWIFTUI-1 — REFUTED

The candidate's central premise is factually wrong on two counts, verified.

1) The iOS branch is NOT a bare Image(uiImage:) that drops template mode.
MathImageRenderer.swift:144 bakes the rendering mode into the UIImage itself:
`if isTemplate { image = image.withRenderingMode(.alwaysTemplate) }`. That
UIImage is what MathView.swift:45 passes to Image(uiImage:).

2) The linchpin assertion "SwiftUI's Image doesn't honor a UIImage's own
renderingMode" is false. Image(uiImage:) respects the underlying
UIImage.renderingMode; an .alwaysTemplate UIImage is tinted by foregroundStyle
without any SwiftUI .renderingMode() modifier. The .renderingMode() view
modifier only exists to OVERRIDE an image's inherent mode. This also makes the
code asymmetry correct rather than buggy: on macOS SwiftUI does not reliably
infer template from NSImage.isTemplate, so the AppKit branch (MathView.swift:43)
applies .renderingMode(.template) explicitly; on iOS the UIImage's own mode is
authoritative and is baked at MathImageRenderer.swift:144. Both branches achieve
template tinting. So "iOS equations never re-tint / vanish on dark canvases"
does not hold.

The secondary rationale (template rendering discards baked ink so
.mathTheme(.dark) ink is overridden for the no-\color case) describes real
behavior but is NOT the asymmetric iOS bug claimed: it is symmetric across both
platforms, and it is the explicitly documented design intent
(MathImageRenderer.swift:116-117 — no explicit \color → tintable template image
so math adapts to the run / dark mode without a re-render). The VinculumLabel
hazard the candidate cites (VinculumLabel.swift:189-190) is a different code
path — drawing a template UIImage raw into a CGContext outside a UIImageView,
where the tint defaults to black — which does not apply to the SwiftUI
Image(uiImage:) path at all. No iOS-only correctness defect exists; the
candidate is rejected.

---

## LAYOUT-5 — REFUTED

Read Layout+Scripts.swift:1-183 in full. Lines 86-92: supX = baseBox.width +
(isLargeOp ? 0 : delta) + supKern; subX = max(0, baseBox.width - (isLargeOp ?
delta : 0) + subKern). Compared this against TeX82: make_op (§749) removes the
italic correction from the operator box width when a subscript is present and
subtype != limits (width(x):=width(x)-delta), then make_scripts shifts the
superscript right by delta relative to the subscript. Net result relative to the
operator's natural glyph width: subscript at width-delta, superscript at width —
exactly the code's isLargeOp branch. Ordinary characters retain the italic
correction in width (§755), giving subscript at width, superscript at
width+delta — exactly the non-largeOp branch. The candidate's stated 'vanilla
TeX Rule 18 is class-independent' premise is incorrect; TeX explicitly
special-cases large operators via make_op. The code is a faithful port, not an
inversion. Rejecting.

---

## SWIFTUI-2 — REFUTED

The candidate's core premise — that a plain MathView "bakes black ink regardless
of the device's color scheme" and is invisible/low-contrast in dark mode — is
factually wrong for the default case, and the design already solves this without
@Environment(\.colorScheme).

Verified in :

1. MathImageRenderer.swift:116-118 sets `isTemplate = !scene.hasExplicitColor`
with the explicit comment: "No explicit \color anywhere → a tintable template
image, so selected math inverts with the run and dark-mode adapts without a
re-render." This is a deliberate, documented design.

2. MathView.swift:43 (AppKit) renders `Image(nsImage:
r.image).renderingMode(r.image.isTemplate ? .template : .original)`. A SwiftUI
template image is tinted by the foreground style, whose default (.primary) is
appearance-adaptive — black in light mode, white in dark mode. So the theme's
`.light`/.black ink is alpha-only and overridden by SwiftUI's adaptive tint.

3. On iOS, MathImageRenderer.swift:144 marks the image `.alwaysTemplate` when
there's no explicit color, and MathView.swift:45 uses `Image(uiImage: r.image)`
with no rendering-mode override, so SwiftUI honors `.alwaysTemplate` and applies
the same adaptive foreground tint.

Therefore, for the default/common case (no explicit \color), a plain MathView
already follows the ambient color scheme automatically; the default `theme =
.light` (MathView.swift:20) does not bake visible black ink.

The "iOS renderingMode bug" the candidate treats as a compounding factor exists
only in VinculumLabel's hand-rolled CoreGraphics draw path
(VinculumLabel.swift:186-191, where a template image would otherwise tint to
black outside a UIImageView) and is already explicitly handled there via
withTintColor. It does not apply to MathView, which goes through SwiftUI's
Image.

Adding @Environment(\.colorScheme)-driven theme selection would be redundant
with — and arguably worse than — the existing template-tint mechanism, which
also handles selection inversion (list-row highlight) that a colorScheme read
cannot. The only case where the render is genuinely baked (isTemplate=false) is
when the author supplied explicit \color, where scheme adaptation is
intentionally not wanted. No defect.

---

## FONT-3 — REFUTED

Read MathAssembly.swift:120-176 in full. Verified: (1) line 128 loop is 0...32 =
33 iterations; (2) for a no-extender assembly seq is identical each iteration.
BUT the impact claim fails: lines 162/165 return on the first iteration
(repeats==0) whenever target is reachable, so there is no 33x recompute in the
common case; only the line-172 fallthrough (target unreachable) loops fully.
Real stretchy delimiters have extender parts, so the loop does genuine distinct
work per iteration — not wasted. A no-extender assembly is degenerate in
OpenType MATH (would be a size variant, not an assembly). The candidate's
rationale ('wasted work on every stretchy paren') is false; the proposed
short-circuit guards a path effectively never taken. Micro-opt of a non-path.

---

## API-5 — REFUTED

Verified Sources/VinculumRender/VinculumLabel.swift. Line 53 matches the quoted
code and refreshIfNeeded() (lines 89-93) does synchronously run the coalesced
render. But this is a deliberate, documented design, not a defect: (1) Lines
51-52 explicitly document "Reading this flushes any pending (coalesced) refresh,
so it is always current" — the flush is the property's purpose. (2) The
candidate's suggested fix (reflect only the last-completed refresh) would break
the class's advertised never-half-broken contract, where a host reads isRendered
right after setting latex to decide fallback (lines 24-26); a stale value
defeats that. (3) It mirrors intrinsicContentSize (line 138), which also calls
refreshIfNeeded() on read — lazy-compute-on-getter is idiomatic AppKit/UIKit.
(4) The side effect is conditional (early-returns unless needsRefresh, line 90)
and cached (MathImageRenderer bitmap cache, lines 22-23/96), so a repeated probe
in steady state does no work — contradicting the "unexpected synchronous
rasterization purely by reading" premise. Renaming a public property would be a
breaking change for negative value. Non-issue.
