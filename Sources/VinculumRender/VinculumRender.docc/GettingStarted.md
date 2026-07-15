# Getting Started

Add the package, pick an entry point, render math.

## Add the dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/2389-research/Vinculum.git", from: "1.0.0"),
]
```

Depend on `VinculumRender` (Apple platforms — everything below), or on
`VinculumLayout` alone for platform-free parsing and layout (builds on
Linux; you supply the measurer and renderer).

## The three entry points

**Documents** — when you have prose with embedded math (the common case:
markdown, chat messages, LLM responses):

```swift
let styled = MathText.attributedString(
    from: response,             // "$…$", "$$…$$", "\(…\)", "\[…\]"
    baseFont: .systemFont(ofSize: 15),
    mathTheme: .light,
    mathFont: .latinModern)
```

**Views** — when the equation is the whole view:

```swift
let label = VinculumLabel()                  // AppKit / UIKit
label.latex = #"\sum_{i=1}^{n} i^2"#
label.font = .pagella

MathView(#"e^{i\pi} + 1 = 0"#)               // SwiftUI
    .mathFont(.stixTwo)
```

**Attachments** — when you're composing rich text yourself:

```swift
if let math = MathImageRenderer.attachmentString(
    latex: latex, display: false, mathTheme: .light, baseSize: 15) {
    storage.append(math)     // flows on the text baseline
}
```

## The contract

`attachmentString` and friends return `nil` only when the LaTeX contains
something Vinculum doesn't support — so your app keeps its own fallback
and a document never renders half-broken. Check
`MathParser.isFullySupported(_:)` to gate ahead of time, and
`MathParser.diagnostics(for:)` for messages with source ranges.
