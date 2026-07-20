# Vinculum for Android — Kotlin bridge (B0)

The Kotlin side of the native Android backend: decode the `VDL1` display list
that `libVinculumAndroid.so` produces and draw it on an `android.graphics.Canvas`.
No font on the Kotlin side — the display list carries every glyph as filled
outlines, so this is pure geometry.

## Proven on-device

`x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}` rendered on an API-34 x86_64 emulator, the
full pipeline:

```
Kotlin VinculumNative.render(latex)
  → JNI → vinculum_render_displaylist (Swift core: parse → TeX layout → FreeType outlines)
  → VDL1 bytes → VinculumWire.decode  (15 ops)
  → SceneRenderer.draw(canvas)        (fills paths + rects, one y-flip)
  → a 240×90 PNG of the quadratic formula, correct down to the stretched radical.
```

Logged: `decoded ops=15 w=223.6 h=73.1 … WROTE quadratic.png 240x90`.

## Files

| file | role |
| --- | --- |
| `src/main/kotlin/ai/vinc/VinculumWire.kt` | decodes `VDL1` → a `DisplayList` (the Kotlin twin of Swift `DisplayListWire`) |
| `src/main/kotlin/ai/vinc/SceneRenderer.kt` | draws a `DisplayList` on a `Canvas` (or to a `Bitmap`) |
| `src/main/kotlin/ai/vinc/VinculumNative.kt` | the JNI binding (`renderBytes`, `setFontDir`, `abiVersion`) |
| `demo/DemoActivity.kt` | the on-device proof harness (renders the quadratic to a PNG) |
| `demo/vincjni.c` | the JNI shim linking Java natives to the C ABI |

## Building (until the Gradle/AAR packaging lands — #84)

Manual pipeline, verified on a Linux host with Docker (see `android/smoke/README.md`
for the native `.so` build; this adds the Kotlin layer):

1. Build `libVinculumAndroid.so` + `libvincjni.so` (from `demo/vincjni.c`) per ABI.
2. `kotlinc -classpath android.jar -d classes src/main/kotlin/ai/vinc/*.kt demo/DemoActivity.kt`
3. `d8 --lib android.jar --classpath kotlin-stdlib.jar --min-api 24 <classes> kotlin-stdlib.jar`
4. `aapt2 link … -A assets` (fonts under `assets/fonts/`), add `classes.dex` + `lib/<abi>/*.so`, `zipalign`, `apksigner`.

## Still to build (the rest of the B-track)

- **#81 Compose `Math()`** — the flagship: a `@Composable` drawing the display
  list on a Compose `Canvas`, `LocalContentColor`-themed, with a bitmap cache
  keyed by `(latex, size, scale, color)`.
- **#82** classic `View` + span · **#83** Markwon plugin.
- **#84** Gradle/AAR packaging, ABI splits, Maven, and a JVM unit test that
  decodes the committed `displaylist-wire-v1.bin` fixture (locks Kotlin↔Swift
  wire compatibility without an emulator).
