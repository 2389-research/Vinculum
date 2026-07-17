# Issue Remediation Plan

A sequenced plan to close the 47 issues (#1–#47) raised by the July-2026
multi-expert review. Grouped into six phases, ordered so that **safety nets land
before behavior changes, correctness before enhancement, and big code-motion
happens in one window while the tree is green.**

Issues carry `area:*` / `kind:*` / `priority:*` labels; this plan adds a
**milestone per phase** (P0…P5). Full context is in each issue.

## Guiding principles

- **Never regress the fallback contract.** Unsupported input degrades to visible
  source; every fix keeps that.
- **Test-first, and re-bless goldens knowingly.** Visual-changing fixes
  (LINUX-1/5, LAYOUT-1/2/3/4/6) must show up as deliberate golden diffs, never a
  wholesale re-bless.
- **Additive by default; batch the breaking changes.** The only source-breaking
  items (API-3 namespacing, possibly API-4) are quarantined in Phase 2 so a
  single minor/major bump covers them.
- **Keep Apple ↔ Linux parity.** Layout is platform-free; changes are verified on
  both backends via the parity corpus and (new) Linux goldens.

## Versioning

This plan changes real behavior (correctness fixes + features), so it lands as
genuine releases rather than doc bumps:

- **1.4.2 — shipped 2026-07-16.** The first slice of Phases 0–1: Linux font
  metrics (#1), the two parser data-loss bugs (#2, #9), FreeType memory/thread
  safety (#4, #3), plus the P0 nets (reproducible Linux CI #32, Linux goldens
  #11). No API change → a patch.
- **1.5.0 — shipped 2026-07-16.** The rest of Phase 1, and **Phase 1 is now
  complete (16/16)**: `\nolimits` (#20), amsmath display style in aligned blocks
  (#21), the parser's silent content loss on unterminated arguments (#8), three
  accessibility bugs (#6, #7, #26), the truncated variant ladder (#36), plus the
  test nets (#12, #46). **This was planned as a 1.4.3 patch and became a minor
  bump**: #20 needs a new `MathNode` case, which is source-breaking for exhaustive
  client switches. The version was planned for Phase 2's rename; that now needs
  **1.6.0**.
- Phase 2's API-3 rename is source-breaking → cut it (and API-4) in a **1.6.0**
  (or **2.0.0** if we treat the renames as major) so consumers move once.
- Phases 3–5 → subsequent minor/patch releases.

---

## Phase 0 — Foundations & CI (unblock, zero behavior change)

Make the build trustworthy and establish regression nets **before** touching
behavior. All low-risk, mostly non-product.

| # | Issue | Approach |
|---|---|---|
| #32 | CI-1 · pin Silica/Cairo | Pin the LinuxRaster CI job off `branch:master` to a resolved commit set; the only raster check must be reproducible. Unblocks all Linux work. |
| #11 | TEST-1 · Linux pixel goldens | Stand up a Silica golden suite + fixtures + CI gate, baselining **current** output (the macOS golden suite is the template). This is the net that catches LINUX-1/5. |
| #29 | TEST-3 · move generators out | Relocate the doc/marketing image generators out of the correctness test target so test signal ≠ asset generation. |
| #30 | TEST-4 · perf regression tracking | Extend the profiler (`MathProfileTests`) to emit machine-readable numbers + a threshold gate; ungate the headless test in CI. |
| #31 | TEST-5 · CONTRIBUTING drift | Fix stale version/toolchain metadata; add a CI grep-and-compare so it can't re-drift. (Its release-automation follow-up → Phase 5.) |
| #47 | DOCS-1 · ARCHITECTURE drift | Correct the "add a new command" checklist (claimed vs actual exhaustive switches); add a grep hint. |

**Exit:** Linux CI is deterministic; macOS + Linux goldens and a perf gate guard everything downstream; docs match reality.

---

## Phase 1 — Correctness (highest value: wrong output / unsafe memory)

Ordered by blast radius. Guarded by the Phase 0 nets. TEST-2 and TEST-7 land here
to prove the memory/concurrency fixes.

| # | Issue | Approach |
|---|---|---|
| #1 | **LINUX-1 (high)** · fonts fall back to LM constants | Extract the `MATH` table from the OTF via FreeType and feed *that* to `MathTableParser` — so all five bundled fonts use their own constants on Linux. One shim include + one wrapper method + one call-site; discriminating test + Linux golden diff. |
| #4 | LINUX-2 · dangling font pointer | Give `FreeTypeFont` real ownership of the font bytes (drop the ephemeral `withUnsafeBytes` borrow held for the face's lifetime); fix `init?`/`deinit`. |
| #3 | CONC-1 · `FT_Face` data race | Lock (or make per-thread) the shared `FT_Face` mutation in `FT_Load_Glyph`, or drop the `@unchecked Sendable` claim. |
| #2 | PARSER-1 · stateful switch eats `\end` | Add `\end` to `endsStatefulScope`; + parser tests. |
| #8 | PARSER-2 · missing brace eats formula | Shared `readBraceName` with a defined EOS contract across the four inline loops. |
| #9 | PARSER-3 · `a_b_c` drops an atom | Fix `attachScriptsAndPrimes` to diagnose/keep repeated same-direction scripts instead of silently dropping. |
| #10 | LAYOUT-1 · cramped bit dropped | Propagate the inherited cramped flag into superscript/numerator subtrees (TeX `sup_style`/`num_style`); regression test. |
| #20 | LAYOUT-2 · `\nolimits` discarded | Add a node case/flag and thread it through the ~4 `.limitsOperator` switch sites. |
| #21 | LAYOUT-3 (plausible) · aligned cell style | Verify, then lay `aligned`/`align` cells at display style; re-bless affected goldens. |
| #5 | APPLE-1 · cache cost ignores scale | Compute `NSCache` cost in pixel-space (× backing scale²). |
| #6 | APPLE-2 · iOS VoiceOver stamp lost off-main | Ensure the accessibility label survives off-main first render; on-device VoiceOver check. |
| #17 | APPLE-3 · iOS raster scale not in key | Thread render scale through the entry points and into the cache key. |
| #7 | UIKIT-1 · fallback exposes raw LaTeX to VoiceOver | Narrow the accessibility element when the label renders nothing. |
| #36 | FONT-2 · truncated variant ladder | Reject/handle truncated `MathVariants` construction data; targeted parser test. |
| #26 | SWIFTUI-4 · `.isImage` trait | Mark `MathView` as static text for VoiceOver; manual verification. |
| #12 | TEST-2 · fuzz never hits rasterizers | Add per-backend fuzz that reaches FreeType/Cairo/CoreText (guards LINUX-2/CONC-1). |
| #46 | TEST-7 · concurrency stress | Stress the render/measure caches (guards CONC-1). **Shipped without TSan** — it cannot run for this package: SwiftPM/xcodebuild inject it into Apple-signed `xctest`, which dyld blocks, and the iOS-simulator flag reports success while instrumenting nothing (a deliberate race went unflagged). See the note in `RenderCacheConcurrencyTests`. |

**Exit:** ✅ **met** — shipped as 1.4.2 + 1.5.0 (2026-07-16). No known wrong-output or memory/concurrency defects remain in this phase.

---

## Phase 2 — Refactor, DRY & the breaking renames (pure code motion)

Do the large moves and the one source-breaking rename in a single window while
behavior is frozen and tests are green.

| # | Issue | Approach |
|---|---|---|
| #19 | PARSER-4 · decompose `commandNode` | Split the ~400-line/68-case switch into `MathParser+*.swift` extensions by family; pure code motion, no output change. |
| #18 | FONT-1 · dedup Coverage/u16 reader | Extract the shared OpenType Coverage-table parser + `u16` reader used by `MathTableParser`/`GsubScriptStyleParser`. |
| #37 | PARSER-5 · dedup name↔glyph↔enum maps | Consolidate the hand-duplicated delimiter/accent/x-arrow tables; guard with round-trip + speech snapshots. |
| #41 | **API-3 · namespacing (breaking)** | Rename inconsistent public types to the `Math*` convention; compiler-enforced; **batch into the same release.** |
| #13 | CONC-2 · MathView Sendable closures | Remove the non-Sendable capture in the `alignmentGuide` closures. |

**Exit:** parser and font-parsing are decomposed/DRY; the public type surface is
consistent; breaking changes are done — cut the minor/major bump.

---

## Phase 3 — Platform parity & performance (Linux + caching)

Close the Apple↔Linux daylight (the ROADMAP LP lanes) and the caching gaps.

| # | Issue | Approach |
|---|---|---|
| #15 | LINUX-3 · Linux render has zero caching | Add measurement + per-resource font/constants caches to `MathSilicaRenderer`/`FreeTypeFont`. |
| #34 | LINUX-5 · MATH refinements unwired | FreeType-backed providers (ssty, delimiter variants, accents) so Linux draws the parsed refinements, not just base services. |
| #16 | LINUX-4 · silent `.notdef` | Add a missing-glyph diagnostic seam; optionally a fallback face for scalars absent from the math font. |
| #35 | LINUX-6 · smoke tool hardcoded paths | Parameterize `VinculumLinuxSmoke`; add an advisory CI step. |
| #33 | CONC-4 · coalesce cache misses | Single-flight racing identical renders in `rendered(...)`. |
| #14 | CONC-3 (plausible) · eager AppKit raster | Optionally rasterize eagerly (or document the deferred-paint behavior from the perf report); light template check. |

**Exit:** Linux parity corpus renders indistinguishably; LINUX.md gap table empty; no redundant work under concurrency.

---

## Phase 4 — Enhancements (features)

| # | Issue | Approach |
|---|---|---|
| #25 | SWIFTUI-3 · Dynamic Type | Scale `MathView` with the ambient content-size category. |
| #44 | SWIFTUI-6 · Equatable | Conform so SwiftUI can skip `body` on unrelated re-renders (decide font-equality semantics). |
| #28 | SWIFTUI-7 · demo incremental typeset | Re-typeset only changed ranges; preserve scroll. |
| #27 | SWIFTUI-5 · MathView tests/previews/demo | Ink test + previews + a demo screen for the flagship SwiftUI entry point. |
| #43 | UIKIT-2 · alignment leading/trailing + RTL | Add directional alignment honoring layout direction. |
| #38 | PARSER-6 · `\newcommand[…][default]` | Accept the optional-default form. |
| #40 | LAYOUT-7 · `\mathchoice` | New node + parser case + style-keyed dispatch. |
| #22 | LAYOUT-4 · fraction part-size ramp | Move 0.9/0.8 toward TeX's 1.0/0.70 (behind a flag; medium risk — re-bless goldens carefully). |
| #42 | API-4 · distinct font-load failures | Throwing factory distinguishing "not a font" vs "no MATH table". |
| #24 | API-2 · public DTO initializers | Add public inits to `MathHitRegion`/`MathParseIssue`/`RenderedMath`. |
| #23 | API-1 · source-stability contract | Document the `MathElement` extension-point stability policy. |

**Exit:** feature gaps from the audit closed; coverage matrix updated.

---

## Phase 5 — Hygiene & release automation

| # | Issue | Approach |
|---|---|---|
| #39 | LAYOUT-6 · name Rule 18a constants | Name the 0.25/0.15 ink-floor literals; scope the guard (maintainer call). |
| #45 | TEST-6 · iOS sim suite coverage | Broaden `-only-testing` (2→7 UIKit suites) or document why. |
| — | TEST-5 follow-up · **release automation** | Tags → GitHub Release (and the App-Store/TestFlight pipeline) — the deferred CI/CD work; see the separate release-automation doc. |

**Exit:** no debt literals; CI covers the UIKit surface; releases are one tag.

---

## Effort rollup

Most issues are **Small / low-risk** per the validators. The **Moderate** ones to
budget for: LINUX-1 (#1), PARSER-4 (#19), LINUX-3 (#15), LINUX-5 (#34),
LAYOUT-4 (#22), and the API-3 rename (#41). The rest are hours-scale.

**Recommended cadence:** land Phase 0 (a day of CI/test scaffolding), then work
Phase 1 top-down (correctness first — LINUX-1, LINUX-2, CONC-1 lead), cut a
release, then Phase 2's refactor+rename in one branch, then Phases 3–5 as
capacity allows.
