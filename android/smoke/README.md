# Android JNI smoke harness — the on-device proof (C0c)

This is the minimal harness that proved Vinculum's Swift core **renders LaTeX on
real Android**. It is not the shipping bridge (that's the Kotlin B-track); it's
the end-to-end proof that the native pipeline works under a real ART process
through the app linker namespace — the thing a bare `adb shell` exec cannot show.

**Result, on an API-34 x86_64 emulator:**
```
VINCSMOKE: SUPPORTED   OK abi=1 bytes=2681 magic=VDL1
VINCSMOKE: UNSUPPORTED  NIL abi=1
VINCSMOKE: DONE
```
`x = \frac{-b}{2a}` renders to a 2681-byte `VDL1` display list — **byte-identical
to the Linux build** — and `\notacommand{x}` returns nil (the never-half-broken
contract, upheld across JNI on-device).

## The pipeline this exercises

```
Java render("…")  →  JNI (smoke.c)  →  vinculum_render_displaylist  (C ABI, #77)
  →  parse → TeX layout → FreeType outlines → DisplayList → VDL1 bytes
  →  back to Java as "OK bytes=N magic=VDL1"
```

## Building it (reproducible; needs a Linux host with Docker)

The environment: the Swift **6.2.0-RELEASE** toolchain (pinned to match the SDK —
the floating `swift:6.2` tag drifts), finagolfin's swift-6.2 Android SDK, and
Android build-tools 34.

1. **Cross-build FreeType for the target ABI** — [`scripts/build-freetype-android.sh`](../../scripts/build-freetype-android.sh).
2. **Build `libVinculumAndroid.so`** (the `.dynamic` product), linking that FreeType:
   ```
   swift build --swift-sdk <abi>-unknown-linux-android24 --traits FreeTypeRaster \
     -Xcc -I<ft-include> -Xlinker -L<ft-lib> --product VinculumAndroid
   ```
3. **Build the JNI shim** `libsmoke.so` from `smoke.c`, linking `-lVinculumAndroid`
   (Android clang, `-shared -fPIC`, same `-resource-dir`/`-fuse-ld=lld` as the FreeType build).
4. **Package the APK**: compile `MainActivity.java` (`javac` + `d8`), `aapt2 link`
   with `-A assets` (fonts under `assets/fonts/`), add `classes.dex` and
   `lib/<abi>/*.so` (the two above **plus the Swift/Foundation runtime `.so`s**
   from the SDK sysroot's `usr/lib/<abi>-linux-android/`), `zipalign`, `apksigner`.
5. **Run**: `adb install`, `am start -n com.vinc/.MainActivity`, read `adb logcat | grep VINCSMOKE`.

## The one Android-specific code change this required

`Bundle.module` (SwiftPM's resource-bundle accessor) **fatal-errors inside an
APK** — there is no `.bundle` next to the `.so`. So `FreeTypeFonts` gained an
injectable `fontDirectory`, set via the `vinculum_set_font_dir` C ABI: the host
ships the `.otf`s as APK assets, extracts them once to `filesDir`, and hands over
the path. On Apple/Linux the override stays nil and `Bundle.module` works as
before. Covered by `VinculumWireCTests.testFontDirectoryOverrideMatchesBundleModule`.

## What's left for the real bridge (B-track)

This harness draws nothing — it decodes only the header. The Kotlin `SceneRenderer`
(#80) parses the full `VDL1` buffer and paints it on a `Canvas`; `Math()` (#81),
the AAR packaging (#84), and per-ABI builds follow. This proves the foundation
they build on is sound on-device.
