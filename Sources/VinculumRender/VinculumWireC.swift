// The C ABI the Android JNI layer calls (#77, docs/ANDROID.md): UTF-8 LaTeX in,
// a serialized `DisplayList` (VDL1 bytes) out, null for unsupported. The boundary
// is one-way — Vinculum measures with FreeType in-Swift, so nothing calls back
// into Kotlin (unlike a native-font backend that needs a measure callback).
//
// GATING: the FreeType tier is now trait-separated from Cairo — the
// `FreeTypeRaster` trait (which `LinuxRaster` enables) links only CFreetypeShim,
// so this whole path builds and tests on Linux WITHOUT Cairo, the config Android
// needs. The one remaining Android-specific step is adding the `.android`
// platform to CFreetypeShim's condition in Package.swift once the Swift Android
// SDK is in play (C0/#75) — the platform triple can't be targeted before then.
#if canImport(CFreetypeShim) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import VinculumLayout

/// The ABI-stable core: LaTeX → serialized `DisplayList` bytes (`VDL1`), or nil
/// when the LaTeX is unsupported or lays out to nothing. Testable directly; the
/// `@_cdecl` entry below is a thin pointer-marshalling shell around it.
///
/// Returning nil for unsupported input is the never-half-broken contract carried
/// across the boundary — the host shows its own fallback, exactly as
/// `MathImageRenderer.rendered` returns nil on Apple.
func renderDisplayListWire(latex: String, display: Bool, baseSize: CGFloat,
                           resource: String = "latinmodern-math") -> [UInt8]? {
    guard let (_, font) = FreeTypeFonts.loadFont(resource: resource) else { return nil }
    let node = MathParser.parse(latex)
    guard MathParser.isFullySupported(node) else { return nil }
    let constants = FreeTypeFonts.mathConstants(for: font) ?? .latinModern
    let engine = MathLayoutEngine(
        services: MathFontServices(measure: FreeTypeFonts.freeTypeMeasurer(font: font),
                                   constants: constants),
        baseSize: display ? baseSize * 1.15 : baseSize)
    let scene = engine.layout(node, display: display)
    guard scene.width > 0, scene.height > 0 else { return nil }
    let list = MathDisplayListRenderer.displayList(for: scene, outliner: FreeTypeOutliner.make(font: font))
    return DisplayListWire.serialize(list)
}

// MARK: - C ABI

/// The ABI version, so the Kotlin side can refuse a mismatched `.so`.
@_cdecl("vinculum_abi_version")
public func vinculum_abi_version() -> Int32 { 1 }

/// Sets the directory the bundled `.otf` fonts are loaded from, replacing the
/// `Bundle.module` lookup that traps inside an APK. The Android host extracts the
/// fonts (shipped as APK assets) once and passes their directory here before the
/// first render. Pass nil to clear. See `FreeTypeFonts.fontDirectory`.
@_cdecl("vinculum_set_font_dir")
public func vinculum_set_font_dir(_ dirPtr: UnsafePointer<CChar>?) {
    FreeTypeFonts.fontDirectory = dirPtr.map { String(cString: $0) }
}

/// Renders `latex` (UTF-8, `byteLen` bytes) to a freshly allocated buffer of
/// `outLen` bytes (a `VDL1` display list), or returns nil for unsupported or
/// malformed input. The caller owns the buffer and MUST release it with
/// `vinculum_free`. `outLen` is set to 0 on any nil return.
@_cdecl("vinculum_render_displaylist")
public func vinculum_render_displaylist(_ latexPtr: UnsafePointer<CChar>?,
                                        _ byteLen: Int32,
                                        _ display: Int32,
                                        _ baseSize: Double,
                                        _ outLen: UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<UInt8>? {
    outLen?.pointee = 0
    guard let latexPtr, byteLen >= 0 else { return nil }
    let data = Data(bytes: UnsafeRawPointer(latexPtr), count: Int(byteLen))
    guard let latex = String(data: data, encoding: .utf8),
          let bytes = renderDisplayListWire(latex: latex, display: display != 0,
                                            baseSize: CGFloat(baseSize)) else { return nil }
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    buf.initialize(from: bytes, count: bytes.count)
    outLen?.pointee = Int32(bytes.count)
    return buf
}

/// Releases a buffer returned by `vinculum_render_displaylist`. Null-safe.
@_cdecl("vinculum_free")
public func vinculum_free(_ ptr: UnsafeMutablePointer<UInt8>?) {
    ptr?.deallocate()
}
#endif
