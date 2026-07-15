# Rendering Documents

Prose with embedded math is the dominant real-world input — render it in
one call.

## Overview

``MathText/attributedString(from:baseFont:textColor:mathTheme:mathFont:)``
takes a whole string and returns an `NSAttributedString`:

- **All four delimiter styles**: `$…$` and `\(…\)` inline; `$$…$$` and
  `\[…\]` display. Escaped `\$` is a dollar sign.
- **Display math** sits on its own centered paragraph.
- **Macros are document-scoped**: a `\newcommand` in one segment applies
  to every later segment; definition-only segments render nothing.
- **Unsupported math stays visible** as styled monospaced source — a
  document is never silently missing an equation.

## LLM output

Model responses arrive with `\(…\)` and `\[…\]` math throughout. Feed the
response straight in:

```swift
let styled = MathText.attributedString(from: modelResponse,
                                       baseFont: bodyFont)
messageView.textStorage?.setAttributedString(styled)
```

Every rendered equation carries a spoken-math `accessibilityLabel`
generated from the same tree that was typeset, so VoiceOver reads the
mathematics, not "image".

## Performance

Rendering is cached by content + theme + size + font. Repeated equations
across a conversation are dictionary hits (~microseconds); a cold render
of a typical equation is well under a millisecond. Unsupported input is
cached negatively, so a live editor doesn't re-parse known-bad LaTeX on
every keystroke.
