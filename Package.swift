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
//   .package(url: "…/Vinculum", from: "1.4.1", traits: ["LinuxRaster"])
//
// or build/test with `--traits LinuxRaster`. (`Package.resolved` is
// git-ignored: a committed trait-on lockfile would re-pull Cairo even for
// default builds.)
let package = Package(
    name: "Vinculum",
    platforms: [.macOS(.v14), .iOS(.v17), .visionOS(.v1), .tvOS(.v17)],
    products: [
        .library(name: "VinculumLayout", targets: ["VinculumLayout"]),
        .library(name: "VinculumRender", targets: ["VinculumRender"]),
    ],
    traits: [
        .trait(
            name: "LinuxRaster",
            description: "Link the Silica/Cairo raster rendering backend (Linux only). "
                + "Off by default so no-trait consumers keep a Silica-free dependency graph."
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
                    .target(name: "CFreetypeShim",
                            condition: .when(platforms: [.linux], traits: ["LinuxRaster"])),
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
        .testTarget(name: "VinculumLayoutTests", dependencies: ["VinculumLayout"], path: "Tests/VinculumLayoutTests"),
        .testTarget(name: "VinculumRenderTests", dependencies: ["VinculumRender", "VinculumLayout"], path: "Tests/VinculumRenderTests"),
    ]
)
