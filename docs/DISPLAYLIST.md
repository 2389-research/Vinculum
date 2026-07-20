# The Vinculum display list & the `VDL1` wire format

This is the **portable rendering contract** that lets Vinculum's Swift core hand
a fully-resolved picture to *any* platform's 2D canvas. It is the thing that
unlocked Android, WebAssembly, and Windows: the layout engine emits a
device-independent display list, serializes it to a small binary buffer, and the
host decodes and draws it — no fonts, no text shaping, no Vinculum internals cross
the boundary.

> **Status:** the format is shipping (Swift writer + reader, Kotlin reader) and
> proven byte-identical across Android, Linux, macOS, and Windows via a single
> committed fixture. This document is the authoritative spec; the code
> (`DisplayListWire.swift`, `VinculumWire.kt`) conforms to it, not the reverse.

---

## The display list

A `DisplayList` (`Sources/VinculumLayout/DisplayList.swift`) is a `MathScene`
reduced to nothing but concrete filled/stroked geometry, **with every glyph
already resolved to its outline**. Because it carries no glyph IDs or font
references, a consumer needs only a path/rect rasterizer — never a font engine.

```
DisplayList
  width, ascent, descent : the ink bounds (tight; the consumer adds its own padding)
  ops : [Op]

Op
  fillPath(subpaths: [PathOp], color)          // every glyph, and any filled shape
  fillRect(rect, color)                        // fraction bars, over/underlines
  strokePath(path: [PathOp], width, cap, join, color)   // radicals, braces, arrows

PathOp
  move(p) | line(p) | quad(to, control) | cubic(to, c1, c2) | close
```

**Coordinates are scene-native: y-up, with the origin on the baseline.** Bounds
are tight to the ink. The y-down flip and any padding happen **once, on the
consumer side** (see `SceneRenderer.kt` / `MathSilicaRenderer.png(for:)` for
reference drawers). Colors are concrete — the scene's "theme ink" (`nil`) has
already been resolved to an actual color by serialization time, so the list fully
determines the picture.

Why all-outlines rather than glyph runs? Because the fidelity target is *matching
the Apple/Linux render*, and both of those fill glyph outlines. An all-outlines
list reproduces exactly what they draw — verified pixel-identical against
CoreGraphics and Cairo.

---

## `VDL1` — the wire format

A hand-rolled, **little-endian**, tagged binary. Not FlatBuffers: the package is
dependency-free by charter, a display list is a few KB (the canonical fixture is
144 bytes) so zero-copy buys nothing, and the writer/reader are a few dozen lines
each with no codegen. A Kotlin reader is `ByteBuffer.order(LITTLE_ENDIAN)`; a JS
reader is a `DataView`.

### Byte layout

All integers and floats are little-endian. `f32` = IEEE-754 single. `u32`/`u8` =
unsigned. `rgba` = 4×`u8` in R,G,B,A order.

```
Header
  magic    : 4 bytes  = "VDL1"      (0x56 0x44 0x4C 0x31)
  width    : f32
  ascent   : f32
  descent  : f32
  opCount  : u32
  ops      : opCount × Op

Op   (tagged)
  tag : u8
    0  fillPath    : rgba, segCount:u32, Seg × segCount
    1  fillRect    : rgba, x:f32, y:f32, w:f32, h:f32
    2  strokePath  : rgba, width:f32, cap:u8, join:u8, segCount:u32, Seg × segCount

Seg  (tagged)
  op : u8
    0  move   : x:f32, y:f32
    1  line   : x:f32, y:f32
    2  quad   : tx:f32, ty:f32, cx:f32, cy:f32           (endpoint first, then control)
    3  cubic  : tx:f32, ty:f32, c1x:f32, c1y:f32, c2x:f32, c2y:f32   (endpoint, c1, c2)
    4  close  : —

cap  : 0 butt   | 1 round  | 2 square
join : 0 miter  | 1 round  | 2 bevel
```

**Field order is exact and load-bearing.** In particular `fillPath`/`strokePath`
carry `rgba` **before** the segment list — a decoder must read the color first
(a real bug this caught: a left-to-right-evaluating language that reads segs
before rgba corrupts every filled glyph; see `VinculumWire.kt`).

The `quad`/`cubic` segments store the **endpoint first**, then the control
point(s). Map to a path API accordingly — e.g. Android `Path.quadTo(cx, cy, tx,
ty)` takes control-then-endpoint, so the decoder reorders.

### Versioning

- The `"1"` in the magic **is** the version.
- A reader **must** check the 4-byte magic and **reject** an unknown one (return
  null / error — never guess). That rejection is the compatibility guarantee: an
  old reader refuses new data cleanly rather than misreading it.
- A backward-compatible addition (a new trailing field on an existing op, or a
  new op tag a reader can safely skip) *may* keep `VDL1`.
- Any change that would mislead an old reader **bumps the magic** (`VDL2`) and
  re-cuts the conformance fixtures.

### Robustness (required of every decoder)

A decoder consumes an **untrusted** buffer (it arrives over JNI / FFI). It must:

- Return null/empty — **never trap** — on bad magic, truncation, or an unknown
  tag.
- **Never allocate on an untrusted count.** `opCount`/`segCount` come from the
  buffer; each record is ≥ 1 byte, so a count larger than the remaining bytes is
  a lie. Cap any `reserveCapacity` to bytes actually present. (A forged `opCount`
  once requested a 154 GB allocation and crashed on Linux — this is a real DoS
  vector, not hypothetical.)

---

## Reference implementations

| language | writer | reader |
| --- | --- | --- |
| Swift | `DisplayListWire.serialize` | `DisplayListWire.deserialize` |
| Kotlin | — | `ai.vinc.VinculumWire.decode` |

The C ABI entry `vinculum_render_displaylist` (`VinculumWireC.swift`, `#77`)
returns a `VDL1` buffer for a LaTeX string, or null for unsupported input.

---

## The conformance corpus

`Tests/fixtures/displaylist-wire-*.bin` are the **cross-language ground truth** —
committed binary serializations of canonical display lists covering every op and
segment kind. Any decoder (present or future) is correct iff it reconstructs the
canonical list from these exact bytes.

- Swift: `DisplayListWireTests` (writer is byte-stable against the fixture; reader
  decodes it; malformed input returns nil). Runs on macOS, Linux, **and Windows**.
- Kotlin: `VinculumWire` conformance test (decodes the same bytes) — the twin that
  keeps the two ends from drifting.

Regenerate a fixture only on a deliberate format change (`VINCULUM_UPDATE_WIRE_FIXTURE=1`),
and bump the magic + filename when you do.

---

## Adding a platform (the short version)

1. Get `libVinculumAndroid`-style `.so`/`.dll`/`.wasm` (or run the C ABI directly)
   and call `vinculum_render_displaylist` → a `VDL1` buffer.
2. Write a ~100-line decoder per this spec (or port `VinculumWire.kt`).
3. Write a ~150-line drawer that walks the ops and calls your platform's
   path-fill / rect-fill / path-stroke, applying the single y-flip.
4. Prove it against the conformance corpus, then against the SVG parity gate.

That's the whole cost of a new platform — which is the point of declaring this a
protocol rather than an implementation detail. See
[ANDROID.md](ANDROID.md) for a worked example and [ARCHITECTURE.md](ARCHITECTURE.md)
for where the display list sits in the pipeline.
