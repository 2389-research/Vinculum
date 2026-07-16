#!/usr/bin/env bash
# Build the "Vinculum vs. real TeX" comparison cells.
#
# Renders the same equations two ways — through pdfTeX (Computer Modern) and
# through Vinculum (Latin Modern, the same lineage) — and bakes ONE height-matched
# pair per equation (pdfTeX above Vinculum, same glyph scale, small labels). The
# landing page arranges the pairs in a responsive grid, so the fidelity claim is
# checkable at a glance and fills the width on any window. Baking each pair as a
# single image guarantees the two engines stay at identical scale when it reflows.
# Output: docs/assets/cmp-0.png … cmp-N.png
#
# Requires: pdflatex, magick (ImageMagick), qlmanage, swift. Run from repo root:
#   ./scripts/compare-tex.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
WORK="$(mktemp -d)"
OUT="$ROOT/docs/assets"
mkdir -p "$OUT"
trap 'rm -rf "$WORK"' EXIT

# Kept in lockstep with Tests/VinculumRenderTests/ComparisonGenerator.swift.
EQS=(
  'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}'
  '\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}'
  '\left( \frac{\partial f}{\partial x} \right)_{\! y} \cfrac{1}{1 + \cfrac{1}{x}}'
)
H=150   # matched glyph height (px) for both engines; 2× so it stays crisp scaled

# ImageMagick has no font-name resolution here — give it a real file.
FONT=""
for f in /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/HelveticaNeue.ttc \
         /System/Library/Fonts/Geneva.ttf /System/Library/Fonts/SFNS.ttf; do
  [ -f "$f" ] && { FONT="$f"; break; }
done
[ -n "$FONT" ] || { echo "no usable label font found"; exit 1; }

norm() {  # norm <src> <dst> : trim to ink, flatten on white, normalize to height H
  magick "$1" -background white -alpha remove -trim +repage -resize "x${H}" "$2"
}
label() { # label <text> <color> <dst>
  magick -background white -fill "$2" -font "$FONT" -pointsize 30 label:"$1" \
         -bordercolor white -border 0x4 "$3"
}

echo "==> Rendering ${#EQS[@]} equations through pdfTeX (Computer Modern)…"
# Minimal TeX Live has no standalone/preview and no ghostscript, so we crop the
# page with `geometry` and rasterize the PDF with macOS `qlmanage` (no gs).
for i in "${!EQS[@]}"; do
  cat > "$WORK/tex-$i.tex" <<EOF
\\documentclass[12pt]{article}
\\usepackage{amsmath,amssymb}
\\usepackage[paperwidth=11in,paperheight=3.5in,margin=2pt]{geometry}
\\pagestyle{empty}
\\begin{document}
\\[ ${EQS[$i]} \\]
\\end{document}
EOF
  ( cd "$WORK" && pdflatex -interaction=batchmode -halt-on-error "tex-$i.tex" >/dev/null 2>&1 )
  qlmanage -t -s 2600 -o "$WORK" "$WORK/tex-$i.pdf" >/dev/null 2>&1
  norm "$WORK/tex-$i.pdf.png" "$WORK/tex-h-$i.png"
done

echo "==> Rendering the same equations through Vinculum (Latin Modern)…"
VINCULUM_CMP_DIR="$WORK" swift test --filter ComparisonGenerator/testGenerateComparisonEquations >/dev/null 2>&1
for i in "${!EQS[@]}"; do
  norm "$WORK/vinc-$i.png" "$WORK/vinc-h-$i.png"
done

echo "==> Composing one height-matched pair per equation…"
label 'pdfTeX'   '#8a93a3' "$WORK/lbl-tex.png"
label 'Vinculum' '#2563eb' "$WORK/lbl-vinc.png"
for i in "${!EQS[@]}"; do
  # A little left inset + vertical breathing room around each render.
  magick "$WORK/tex-h-$i.png"  -bordercolor white -border 14x8 "$WORK/tex-p-$i.png"
  magick "$WORK/vinc-h-$i.png" -bordercolor white -border 14x8 "$WORK/vinc-p-$i.png"
  # Stack: pdfTeX label / render / Vinculum label / render, all left-aligned.
  magick "$WORK/lbl-tex.png" "$WORK/tex-p-$i.png" "$WORK/lbl-vinc.png" "$WORK/vinc-p-$i.png" \
         -background white -gravity West -append \
         -bordercolor white -border 20x18 "$OUT/cmp-$i.png"
done

echo "==> Wrote ${#EQS[@]} pairs:"
for i in "${!EQS[@]}"; do
  printf '    cmp-%s.png  %s\n' "$i" "$(magick identify -format '%wx%h' "$OUT/cmp-$i.png")"
done
