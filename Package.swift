// swift-tools-version: 6.2
import PackageDescription

// Vinculum — native LaTeX math parsing and typesetting for Apple platforms.
// VinculumLayout is platform-free (LaTeX → a TeX-style node tree, with
// document-scoped \newcommand macro expansion); VinculumRender lays each
// node out as geometry and draws it with CoreText/CoreGraphics behind a
// small MathTheme seam. No MathJax, no KaTeX, no WebView, no dependencies.
//
// The vinculum is the bar in a fraction, the line over a root — the stroke
// the typesetter draws to bind an expression together.
//
// On Apple platforms VinculumRender draws with CoreText/CoreGraphics and never
// links Silica. On Linux it draws with Silica (Cairo/FreeType) — a raster
// backend behind the `LinuxRaster` trait (default OFF).
//
// ── Why the Silica backend is behind a trait ──
// Silica tracks `master` (it depends on Cairo by branch, so a stable version
// requirement can't be mixed in). Merely platform-conditioning the products
// (`.when(platforms: [.linux])`) was not enough: SwiftPM still RESOLVES every
// declared dependency regardless of platform, so a plain `from:` consumer —
// even Apple-only — was forced to fetch the whole Silica/Cairo/PureSwift graph.
// Package traits (SwiftPM 6.1+) fix it: the Silica dependency and its product
// links are guarded by `LinuxRaster`, which is OFF by default, so a default
// resolve fetches zero external dependencies. Linux users who want the native
// raster backend opt in:
//
//   .package(url: "…/Vinculum", from: "1.5.0", traits: ["LinuxRaster"])
//
// or build/test with `--traits LinuxRaster`. (`Package.resolved` is
// git-ignored: a committed trait-on lockfile at the root would re-pull Cairo
// even for default builds. For reproducible CI the trait-on graph is pinned
// out-of-tree in `ci/Package.resolved.linux`, restored only by the Linux CI
// job — see .github/workflows/ci.yml.)
let package = Package(
    name: "Vinculum",
    platforms: [.macOS(.v14), .iOS(.v17), .visionOS(.v1), .tvOS(.v17)],
    products: [
        .library(name: "VinculumLayout", targets: ["VinculumLayout"]),
        .library(name: "VinculumRender", targets: ["VinculumRender"]),
        // The Android JNI library: VinculumRender as a dynamic `.so`, exporting
        // the C ABI (`vinculum_render_displaylist` etc., #77). Built when
        // cross-compiling with the Swift Android SDK + FreeTypeRaster; on
        // Apple/Linux `swift build` also emits it (a harmless dylib of the same
        // module). See docs/ANDROID.md and scripts/build-freetype-android.sh.
        .library(name: "VinculumAndroid", type: .dynamic, targets: ["VinculumRender"]),
    ],
    traits: [
        // The FreeType TIER on its own: glyph outlines + metrics + MATH-table
        // constants, no Cairo. This is the tier the Android C ABI builds on
        // (Android has FreeType but not Cairo). Enables only the CFreetypeShim
        // link, not the Silica/Cairo graph.
        .trait(
            name: "FreeTypeRaster",
            description: "Link the FreeType glyph/measure path (no Cairo) — the tier the "
                + "Android C ABI uses; also enabled transitively by LinuxRaster."
        ),
        // The Cairo PNG backend, layered on the FreeType tier — so it ENABLES
        // FreeTypeRaster. Off by default so no-trait consumers keep a Silica-free
        // dependency graph.
        .trait(
            name: "LinuxRaster",
            description: "Link the Silica/Cairo raster PNG backend (Linux only). "
                + "Enables FreeTypeRaster. Off by default so no-trait consumers keep a "
                + "Silica-free dependency graph.",
            enabledTraits: ["FreeTypeRaster"]
        ),
    ],
    dependencies: [
        // Guarded by `LinuxRaster`: when the trait is disabled (the default)
        // these are pruned from resolution entirely — no branch dependency
        // reaches a downstream `from:` consumer, and no Cairo/PureSwift graph
        // is fetched on Apple platforms.
        .package(url: "https://github.com/PureSwift/Silica.git", branch: "master"),
        .package(url: "https://github.com/PureSwift/Cairo.git", branch: "master"),
    ],
    targets: [
        .target(name: "VinculumLayout", path: "Sources/VinculumLayout"),
        // Raw FreeType C shim — the Linux backend loads the bundled MATH .otf
        // fonts from bytes and extracts glyph outlines directly (Silica's
        // font-by-name path can't resolve non-default families). Built only
        // under the LinuxRaster trait; Apple never references it.
        .systemLibrary(name: "CFreetypeShim", path: "Sources/CFreetypeShim",
                       pkgConfig: "freetype2",
                       providers: [.apt(["libfreetype6-dev"]), .brew(["freetype"])]),
        .target(name: "VinculumRender", dependencies: [
                    "VinculumLayout",
                    // Both the platform AND the trait must hold: Apple platforms
                    // use CoreGraphics/CoreText and never link these even with
                    // the trait on; the trait gate is what keeps Silica out of
                    // the resolved graph for every no-trait consumer.
                    .product(name: "SilicaCairo", package: "Silica",
                             condition: .when(platforms: [.linux], traits: ["LinuxRaster"])),
                    .product(name: "Cairo", package: "Cairo",
                             condition: .when(platforms: [.linux], traits: ["LinuxRaster"])),
                    // FreeType is the lower tier: available under FreeTypeRaster
                    // alone (the Android/Windows C ABI) OR LinuxRaster (which
                    // enables it), on Linux, Android AND Windows (all have
                    // FreeType; the Android build links a cross-built
                    // libfreetype.a — build-freetype-android.sh; the Windows build
                    // links vcpkg's freetype.lib — see the native-dll CI job).
                    // The three FreeType sources guard on `canImport(CFreetypeShim)`
                    // alone, so admitting .windows here is all it takes to compile
                    // the same C ABI into a Windows DLL.
                    .target(name: "CFreetypeShim",
                            condition: .when(platforms: [.linux, .android, .windows], traits: ["FreeTypeRaster"])),
                ], path: "Sources/VinculumRender",
                resources: [.copy("Resources/latinmodern-math.otf"),
                            .copy("Resources/texgyretermes-math.otf"),
                            .copy("Resources/texgyrepagella-math.otf"),
                            .copy("Resources/stixtwo-math.otf"),
                            .copy("Resources/firamath.otf"),
                            .copy("Resources/LatinModernMath-LICENSE.txt"),
                            .copy("Resources/GUST-FONT-LICENSE.txt"),
                            .copy("Resources/README-TeX-Gyre-Termes-Math.txt"),
                            .copy("Resources/README-TeX-Gyre-Pagella-Math.txt"),
                            .copy("Resources/OFL-STIXTwo.txt"),
                            .copy("Resources/OFL-FiraMath.txt")]),
        .executableTarget(name: "VinculumDemo", dependencies: ["VinculumRender"],
                          path: "Sources/VinculumDemo"),
        .executableTarget(name: "VinculumLinuxSmoke", dependencies: ["VinculumRender"],
                          path: "Sources/VinculumLinuxSmoke"),
        .executableTarget(name: "VinculumWasmSmoke", dependencies: ["VinculumLayout"],
                          path: "Sources/VinculumWasmSmoke"),
        .testTarget(name: "VinculumLayoutTests", dependencies: ["VinculumLayout"], path: "Tests/VinculumLayoutTests"),
        .testTarget(name: "VinculumRenderTests", dependencies: ["VinculumRender", "VinculumLayout"], path: "Tests/VinculumRenderTests"),
    ]
)
