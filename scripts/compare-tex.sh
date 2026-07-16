#!/usr/bin/env bash
# Build the "Vinculum vs. real TeX" comparison figure.
#
# Renders the same equations two ways — through pdfTeX (Computer Modern) and
# through Vinculum (Latin Modern, the same lineage) — and stacks them so the
# fidelity claim is checkable at a glance, not asserted. Output:
#   docs/assets/vs-tex.png
#
# Requires: pdflatex, magick (ImageMagick), swift. Run from the repo root:
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
ROW_H=120   # px each equation is normalized to, so the two engines line up

# ImageMagick has no font-name resolution here — give it a real file.
FONT=""
for f in /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/HelveticaNeue.ttc \
         /System/Library/Fonts/Geneva.ttf /System/Library/Fonts/SFNS.ttf; do
  [ -f "$f" ] && { FONT="$f"; break; }
done
[ -n "$FONT" ] || { echo "no usable label font found"; exit 1; }

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
  magick "$WORK/tex-$i.pdf.png" -background white -alpha remove -trim +repage \
         -resize "x${ROW_H}" "$WORK/tex-$i.png"
done

echo "==> Rendering the same equations through Vinculum (Latin Modern)…"
VINCULUM_CMP_DIR="$WORK" swift test --filter ComparisonGenerator/testGenerateComparisonEquations >/dev/null 2>&1
for i in "${!EQS[@]}"; do
  magick "$WORK/vinc-$i.png" -background white -alpha remove -trim +repage \
         -resize "x${ROW_H}" "$WORK/vinc-n-$i.png"
done

echo "==> Composing side-by-side figure…"
PAD=44; GAP=34; LABEL_W=110
# One panel per equation: [ TeX render ] | [ Vinculum render ], each labeled.
panels=()
for i in "${!EQS[@]}"; do
  # Stack the two engine labels + renders as a 2-row block, TeX on top.
  magick "$WORK/tex-$i.png"  -bordercolor white -border 8x10 "$WORK/tex-p-$i.png"
  magick "$WORK/vinc-n-$i.png" -bordercolor white -border 8x10 "$WORK/vinc-p-$i.png"
  # Row label ("TeX" / "Vinculum") as small gray text to the left.
  magick -background white -fill '#9aa4b4' -font "$FONT" -pointsize 26 \
         -size ${LABEL_W}x label:'pdfTeX' -gravity East "$WORK/lbl-tex-$i.png"
  magick -background white -fill '#2563eb' -font "$FONT" -pointsize 26 \
         -size ${LABEL_W}x label:'Vinculum' -gravity East "$WORK/lbl-vinc-$i.png"
  magick "$WORK/lbl-tex-$i.png"  "$WORK/tex-p-$i.png"  +append "$WORK/row-tex-$i.png"
  magick "$WORK/lbl-vinc-$i.png" "$WORK/vinc-p-$i.png" +append "$WORK/row-vinc-$i.png"
  magick "$WORK/row-tex-$i.png" "$WORK/row-vinc-$i.png" -background white -gravity West -append \
         "$WORK/panel-$i.png"
  panels+=("$WORK/panel-$i.png")
  # Hairline separator between panels (except after the last).
  if [ "$i" -lt "$(( ${#EQS[@]} - 1 ))" ]; then
    W=$(magick identify -format '%w' "$WORK/panel-$i.png")
    magick -size "${W}x1" xc:'#e6e9ef' -bordercolor white -border 0x${GAP} "$WORK/sep-$i.png"
    panels+=("$WORK/sep-$i.png")
  fi
done

magick "${panels[@]}" -background white -gravity West -append \
       -bordercolor white -border ${PAD}x${PAD} "$OUT/vs-tex.png"
# Keep it crisp but not enormous on the page.
magick "$OUT/vs-tex.png" -resize '1400x>' "$OUT/vs-tex.png"
echo "==> Wrote $OUT/vs-tex.png ($(magick identify -format '%wx%h' "$OUT/vs-tex.png"))"
