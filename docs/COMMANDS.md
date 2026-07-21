# Vinculum Command Reference

The exhaustive "does Vinculum support `\foo`?" lookup, generated against the
source of truth: `MathParser.swift` (every structural / decoration command) and
`MathSymbolTable.swift` (404 symbol commands + 37 function-name operators).

Every command listed here renders natively. **Anything not listed degrades to a
named fallback** — the parser turns an unknown command into an `.unsupported`
leaf, `MathParser.isFullySupported` returns `false`, and
`MathParser.unsupportedCommands(in:)` names it so a host can explain why. For
semantics, caveats, and the roadmap gaps, see [COVERAGE.md](COVERAGE.md); for
how to add a command, [ARCHITECTURE.md](ARCHITECTURE.md).

This file is a lookup index, not a semantics spec. Where a command has a caveat
(letters-only alphabets, gated delimiter variants, approximated arrows) it is
noted inline.

**Visual charts.** Every symbol and structural command is rendered to an image
chart — a font-specimen grid per atom class (`sym-relations.png`,
`sym-binary.png`, `sym-operators.png`, `sym-ordinary.png`, …), the function
operators (`sym-functions.png`), and source-beside-render structural examples
(`cmd-structural.png`). CI regenerates them on every push to `main` and
publishes them to the [`gallery` branch](https://github.com/2389-research/Vinculum/tree/gallery),
so they're always current — e.g.
`https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-relations.png`.

---

# Part 1 — Structural & layout commands

Every structural command below, rendered source-beside-result (CI-regenerated):

![Structural commands](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/cmd-structural.png)

## Fractions & stacks

| Command | Example | Note |
| --- | --- | --- |
| `\frac{a}{b}` | `\frac{a}{b}` | Ruled fraction, axis-aligned |
| `\dfrac{a}{b}` | `\dfrac{a}{b}` | Force **display** style |
| `\tfrac{a}{b}` | `\tfrac{a}{b}` | Force **text** style |
| `\cfrac{a}{b}` | `\cfrac{1}{1+\cfrac{1}{x}}` | Full-size continued fraction; optional `[l]`/`[r]` alignment: `\cfrac[l]{1}{x}` |
| `\binom{n}{k}` | `\binom{n}{k}` | Ruleless, paren-fenced |
| `\dbinom{n}{k}` | `\dbinom{n}{k}` | Binom, forced display style |
| `\tbinom{n}{k}` | `\tbinom{n}{k}` | Binom, forced text style |
| `\genfrac{l}{r}{thick}{style}{n}{d}` | `\genfrac{[}{]}{0pt}{}{n}{k}` | Custom delimiters; `thick=0pt`→no rule; `style` `0`=display, `1/2/3`=text |

**Infix (TeX legacy) forms.** `\over`, `\atop`, `\choose`, `\brace`, `\brack`
restructure their enclosing group into numerator-over-denominator. Everything
before the operator is the numerator, everything after is the denominator.

| Command | Example | Note |
| --- | --- | --- |
| `\over` | `{a+b \over c+d}` | Infix `\frac` |
| `\atop` | `{n \atop k}` | Stacked, no rule, no fences |
| `\choose` | `{n \choose k}` | Infix `\binom` (parens) |
| `\brace` | `{n \brace k}` | Braced (Stirling 2nd kind) |
| `\brack` | `{n \brack k}` | Bracketed |

## Roots

| Command | Example | Note |
| --- | --- | --- |
| `\sqrt{x}` | `\sqrt{x+1}` | Square root |
| `\sqrt[n]{x}` | `\sqrt[3]{x}` | Radical with degree index |

## Scripts & primes

| Command | Example | Note |
| --- | --- | --- |
| `^` superscript | `x^2`, `x^{n+1}` | |
| `_` subscript | `x_i`, `a_{ij}` | |
| `'` prime | `f'`, `f''`, `f'^2` | Runs of `'` become ′ superscripts; bind before an explicit `^` |
| `\overset{o}{b}` | `\overset{!}{=}` | `o` set above base `b` |
| `\underset{u}{b}` | `\underset{n\to\infty}{\lim}` | `u` set below base `b` |
| `\stackrel{o}{b}` | `\stackrel{\text{def}}{=}` | Like `\overset` with a relation base |
| `\prescript{sup}{sub}{b}` | `\prescript{14}{6}{C}` | mathtools left scripts (isotopes, tensors); empty groups drop out |
| `\sideset{_l^l}{_r^r}{b}` | `\sideset{}{'}{\sum}` | amsmath scripts at all four corners; the base keeps its own limits |

Big-operator limits are automatic: ∑-class stacks limits above/below in display,
∫-class keeps them to the side, and the `\lim`-family stacks. `\operatorname*`
and `\mathop{…}` force the stacking (limits) form. `\limits` after an operator
forces stacking explicitly (`\int\limits_a^b`), and `\nolimits` forces the
side-set form even in display (`\sum\nolimits_{i=1}^n`) — the usual way to keep
an operator compact inside a display equation. `\displaylimits` is accepted and
is a no-op: it restores the current style's default, which is what an unmodified
operator already does.

## Delimiters

| Command | Example | Note |
| --- | --- | --- |
| `\left … \right` | `\left( \frac{a}{b} \right)` | Auto-sizes fences to the body |
| `\left. … \right)` | `\left. \frac{dy}{dx} \right|_0` | `.` is a null (invisible) fence |
| `\middle` | `\left\{ x \middle| x>0 \right\}` | Extra full-height divider inside `\left…\right` |
| `\big \Big \bigg \Bigg` | `\Big( x \Big)` | Fixed enlargement: 1.2 / 1.8 / 2.4 / 3.0× base |
| …`l`/`r`/`m` suffix | `\bigl( \bigr] \bigm|` | Sets opening / closing / relation spacing class |

Delimiters accepted after `\left`/`\right`/`\middle`/`\big…` include `( ) [ ]`,
`\{ \}` `\lbrace \rbrace`, `| \vert \lvert \rvert`, `\| \Vert \lVert \rVert`,
`\langle \rangle`, `\lceil \rceil \lfloor \rfloor`, `\uparrow \downarrow
\updownarrow \Uparrow \Downarrow`, and `\backslash`. As of 0.24.0 tall
`( ) [ ] { }` use the font's MATH-table size-variant glyphs (constant stroke
weight); other delimiters scale the base glyph continuously.

## Matrices & environments

Use `\begin{env} … \end{env}`; cells split on `&`, rows on `\\`.

| Environment | Example | Note |
| --- | --- | --- |
| `matrix` | `\begin{matrix} a & b \\ c & d \end{matrix}` | Bare grid, no fences |
| `pmatrix` | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` | `( )` fences |
| `bmatrix` | `\begin{bmatrix} … \end{bmatrix}` | `[ ]` fences |
| `Bmatrix` | `\begin{Bmatrix} … \end{Bmatrix}` | `{ }` fences |
| `vmatrix` | `\begin{vmatrix} … \end{vmatrix}` | `\| \|` fences (determinant) |
| `Vmatrix` | `\begin{Vmatrix} … \end{Vmatrix}` | `‖ ‖` fences |
| `smallmatrix` | `\begin{smallmatrix} a & b \\ c & d \end{smallmatrix}` | Script-size inline grid |
| `matrix*[r]` etc. | `\begin{pmatrix*}[r] … \end{pmatrix*}` | Starred variants take an optional column alignment |
| `array` | `\begin{array}{c\|cc} … \end{array}` | Column spec `l`/`c`/`r`, `\|` rules; `p`/`m`/`b`→left |
| `cases` | `\begin{cases} 1 & x>0 \\ 0 & x\le 0 \end{cases}` | Left brace, left-aligned cases |
| `aligned` / `align` | `\begin{aligned} a &= b \\ &= c \end{aligned}` | `&`-aligned equation stack |
| `alignat` / `alignedat` | `\begin{alignat}{2} … \end{alignat}` | Takes an `{n}` column count |
| `split` | `\begin{split} … \end{split}` | Aligned |
| `gather` / `gathered` | `\begin{gather} a \\ b \end{gather}` | Centered rows |
| `multline` | `\begin{multline} … \end{multline}` | Aligned |
| `eqalign` / `displaylines` | `\begin{eqalign} a &= b \\ c &= d \end{eqalign}` | Legacy plain-TeX aliases for the aligned stack |
| `substack` | `\sum_{\substack{0<i<n \\ i\ \text{odd}}}` | Tight vertical stack for limits |
| `CD` (amscd) | `\begin{CD} A @>f>> B \\ @VgVV @VVhV \\ C @>>k> D \end{CD}` | Commutative diagram: objects joined by labelled `@`-arrows (`@>`, `@<`, `@V`, `@A`, `@=`, `@\|`, `@.`) |
| `\ce{…}` (mhchem) | `\ce{2H2 + O2 -> 2H2O}` | Chemistry: auto-subscripts, `^` charges, coefficients, arrows (`->`, `<=>`, `->[cond]`), states `(s)(l)(g)(aq)`, `*` hydrate |
| `\ydiagram{…}` / `\ytableaushort{…}` | `\ydiagram{3,2,1}`, `\ytableaushort{13,2}` | Young diagram (empty boxes from a partition) / filled tableau |
| `axis` (pgfplots subset) | `\begin{axis}[domain=-3:3] \addplot{x^2}; \end{axis}` | Function plot: sampled `\addplot{expr}` curves, auto-ranged axes, ticks, gridlines |
| `\inferrule[…]{…}{…}` (also `\infer`, `\prftree`) | `\inferrule[T\text{-}App]{A \\ B}{C}` | Inference rule / proof tree: premises (`\\`-separated) over a bar over the conclusion, optional label to the right; empty premises = axiom; rules nest |
| `\num` `\ang` `\si`/`\unit` `\SI`/`\qty` (siunitx) | `\SI{9.8}{m/s^2}`, `\num{1.5e3}`, `\ang{45;30;15}` | Units: number formatting (sci-notation, digit grouping), angles (d°m′s″), unit symbols/macros (`\kilo\gram`, `\per`, `\squared`), quantity = number + unit |

A bare `\\` **outside** any environment (an inline line break) is a no-op —
inline math is a single line; multi-line splitting is a host concern.

Row rules inside `array`: `\hline` (full-width rule), `\cline{i-j}` (columns
i…j), `\hdashline`. Unknown environments still lay out as a bare centered grid so
content survives.

`\multicolumn{n}{align}{content}` makes a cell span `n` columns with its own
`l`/`c`/`r` alignment — a title over a table, a merged header, an augmented block.
Content wider than the spanned columns grows the span. Example:

```latex
\begin{array}{cc} \multicolumn{2}{c}{\text{Header}} \\ a & b \end{array}
```

## Accents

Each takes one following atom: `\hat{x}`, `\widehat{AB}`, etc.

| Command | Glyph | Command | Glyph |
| --- | :---: | --- | :---: |
| `\hat` | ̂ | `\check` | ̌ |
| `\tilde` | ̃ | `\bar` | ̄ |
| `\vec` | ⃗ | `\dot` | ̇ |
| `\ddot` | ̈ | `\breve` | ̆ |
| `\acute` | ́ | `\grave` | ̀ |
| `\mathring` | ̊ | `\widehat` | wide ̂ |
| `\widetilde` | wide ̃ | `\widecheck` | wide ̌ |
| `\overrightharpoon` | stretchy ⇀ over | `\overleftharpoon` | stretchy ↼ over |
| `\utilde` | wide ~ **below** | | |
| `\overline` | over-bar | `\underline` | under-bar |

## Over / under decorations

| Command | Example | Note |
| --- | --- | --- |
| `\overbrace{…}^{lbl}` | `\overbrace{a+b}^{s}` | Brace above, optional `^` label |
| `\underbrace{…}_{lbl}` | `\underbrace{a+b}_{s}` | Brace below, optional `_` label |
| `\overbracket` / `\underbracket` | `\overbracket{x}^{n}` | Square bracket variant |
| `\overparen` / `\underparen` | `\overparen{x}` | Parenthesis variant |
| `\overrightarrow` / `\overleftarrow` | `\overrightarrow{AB}` | Vector arrow above base |
| `\overleftrightarrow` | `\overleftrightarrow{AB}` | Bidirectional arrow above |
| `\underrightarrow` / `\underleftarrow` / `\underleftrightarrow` | `\underrightarrow{x}` | Arrow below base |

**Extensible (stretchy) arrows** — `\x…arrow[under]{over}`, optional `[under]`
then `{over}`, stretched to the wider label. Each variant draws its own head:

| Command(s) | Head |
| --- | --- |
| `\xrightarrow` `\xleftarrow` | Single full head |
| `\xLongrightarrow` `\xLongleftarrow` | Double-lined shaft (⟹ ⟸) |
| `\xleftrightarrow` | Heads on both ends (↔) |
| `\xhookrightarrow` `\xhookleftarrow` | Full head + tail hook (↪ ↩) |
| `\xmapsto` | Full head + tail bar (↦) |
| `\xrightharpoonup` `\xrightharpoondown` `\xleftharpoonup` `\xleftharpoondown` | Single-barb harpoon |
| `\xrightleftharpoons` | Opposed stacked harpoons (⇌) |

Example: `\text{H}_2 + \text{I}_2 \xrightleftharpoons[k_r]{k_f} 2\,\text{HI}`.

![Extensible arrows](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/cmd-arrows.png)

## Boxes & decorations

| Command | Example | Note |
| --- | --- | --- |
| `\boxed{…}` | `\boxed{E=mc^2}` | Framed |
| `\fbox{…}` | `\fbox{x}` | Framed (alias of `\boxed`) |
| `\colorbox{c}{…}` | `\colorbox{yellow}{x}` | Filled background |
| `\fcolorbox{b}{c}{…}` | `\fcolorbox{red}{white}{x}` | Border + fill |
| `\rule{w}{h}` | `\rule{2em}{1pt}` | Solid rule of given width/height; optional `[raise]` ignored |
| `\raisebox{d}{…}` | `\raisebox{0.5em}{x}` | Vertical shift |
| `\cancel{…}` | `\cancel{x}` | Diagonal strike |
| `\bcancel{…}` | `\bcancel{x}` | Back-diagonal strike |
| `\xcancel{…}` | `\xcancel{x}` | Cross strike |
| `\cancelto{t}{…}` | `\cancelto{0}{x}` | Strike with a raised target label |
| `\not` | `\not\subset`, `\not=` | Negation slash over the following atom |
| `\phantom{…}` | `\phantom{xyz}` | Occupies size, draws nothing |
| `\hphantom{…}` / `\vphantom{…}` | `\vphantom{\frac12}` | Horizontal / vertical phantom |
| `\smash{…}` | `\smash{\sum}` | Keep width, zero height/depth (`[t]`/`[b]` ignored) |
| `\mathstrut` | `\sqrt{\mathstrut a}` | Invisible paren-height strut |
| `\mathrlap` / `\mathllap` / `\mathclap` | `\mathclap{x}` | Zero-width right / left / center overlap |

## Spacing

| Command | Width | Command | Width |
| --- | --- | --- | --- |
| `\,` / `\thinspace` | 3/18 em | `\!` / `\negthinspace` | −3/18 em |
| `\:` / `\>` / `\medspace` | 4/18 em | `\negmedspace` | −4/18 em |
| `\;` / `\thickspace` | 5/18 em | `\negthickspace` | −5/18 em |
| `\ ` (backslash-space) | 6/18 em | `\enspace` | 1/2 em |
| `\quad` | 1 em | `\qquad` | 2 em |
| `\hspace{…}` / `\kern…` | explicit em/pt | `\mspace{…}` / `\mkern…` | explicit mu |

## Color

| Command | Example | Note |
| --- | --- | --- |
| `\textcolor{c}{…}` | `\textcolor{red}{x}` | Colors the body only |
| `\color{c}{…}` | `\color{blue}{x}` | Colors the braced body |
| `\color{c}` | `x + \color{red} y + z` | Stateful — colors the rest of the current group |

## Math alphabets

Each maps one following atom's letters/digits to the styled codepoint.

| Command | Example | Caveat |
| --- | --- | --- |
| `\mathbb{…}` | `\mathbb{R}` | Blackboard bold; letters + digits |
| `\mathcal{…}` | `\mathcal{L}` | Script; **letters only** (no digits) |
| `\mathscr{…}` | `\mathscr{H}` | Script (same alphabet as `\mathcal`); letters only |
| `\mathfrak{…}` | `\mathfrak{g}` | Fraktur; **letters only** |
| `\mathsf{…}` | `\mathsf{AB}` | Sans-serif; letters + digits |
| `\mathtt{…}` | `\mathtt{code}` | Monospace; letters + digits |
| `\mathbf{…}` | `\mathbf{v}` | Bold via **system font** (not a codepoint) |
| `\boldsymbol{…}` / `\bm{…}` | `\boldsymbol{\alpha}` | Bold-italic |
| `\pmb{…}` | `\pmb{+}` | Poor-man bold ≈ `\mathbf` |
| `\mathrm{…}` / `\textrm{…}` | `\mathrm{d}x` | Upright roman |
| `\text{…}` | `\text{if } x>0` | Upright text; embedded `$…$` renders as math |
| `\operatorname{…}` | `\operatorname{lcm}` | Roman operator name |
| `\operatorname*{…}` | `\operatorname*{argmax}` | Operator with stacked limits |
| `\DeclareMathOperator{\c}{…}` | `\DeclareMathOperator{\argmax}{arg\,max}` | Defines `\argmax` as `\operatorname{…}` (`*` → limits); document-scoped |
| `\mathchoice{D}{T}{S}{SS}` | `\mathchoice{\sum}{\textstyle\sum}{…}{…}` | Picks one branch by the current math style |

Alphabet holes (letters encoded outside the contiguous math block, e.g. `\mathbb{R}`→ℝ,
`\mathcal{H}`→ℋ) are mapped correctly.

**Old-style (plain-TeX) font switches.** Unlike the `\math…{…}` argument
forms, these are *stateful*: they apply to the rest of the current group
(scope them with braces, e.g. `{\cal C}`). Common in legacy and hand-written
LaTeX. `\vec{\bf E}` and `{\cal C}` are the usual shapes.

| Switch | Equivalent | Switch | Equivalent |
| --- | --- | --- | --- |
| `\bf` | `\mathbf` | `\cal` | `\mathcal` |
| `\rm` | `\mathrm` (upright) | `\frak` | `\mathfrak` |
| `\it` / `\sl` / `\mit` | italic | `\bb` | `\mathbb` |
| `\sf` | `\mathsf` | `\scr` | `\mathscr` |
| `\tt` | `\mathtt` | | |

## Atom-class overrides

Force the inter-atom spacing class of a subexpression.

| Command | Class | Command | Class |
| --- | --- | --- | --- |
| `\mathbin{…}` | binary | `\mathrel{…}` | relation |
| `\mathop{…}` | large operator (stacks limits) | `\mathord{…}` | ordinary |
| `\mathinner{…}` | inner (thin-spaced subformula) | | |
| `\mathopen{…}` | opening | `\mathclose{…}` | closing |
| `\mathpunct{…}` | punctuation | | |

## Operators & modular arithmetic

37 function-name operators are recognized (upright, with operator spacing):

`\sin \cos \tan \cot \sec \csc \arcsin \arccos \arctan \sinh \cosh \tanh \coth
\sech \csch \log \ln \lg \exp \min \max \sup \inf \lim \det \dim \ker \arg \gcd
\deg \mod \Pr \hom \argmin \argmax \limsup \liminf`

| Command | Example | Note |
| --- | --- | --- |
| `\pmod{n}` | `a \equiv b \pmod{n}` | Parenthesized `(mod n)` |
| `\bmod` | `a \bmod n` | Binary `mod` |
| `\pod{n}` | `a \pod{n}` | Parenthesized without "mod" |

## Equation tags & numbering

| Command | Example | Note |
| --- | --- | --- |
| `\tag{…}` | `x=1 \tag{1}` | Appends `(1)` inline (flush-right is a host concern) |
| `\tag*{…}` | `x=1 \tag*{$\star$}` | Tag without parentheses |
| `\notag` / `\nonumber` | `x=1 \notag` | No-op (Vinculum has no auto-numbering to suppress) |

## Macros

`\newcommand` / `\renewcommand` / `\def` are expanded before typesetting
(supports `#1`…`#9`, optional `[argc]`, recursion cap). See COVERAGE.md.

```latex
\newcommand{\abs}[1]{\left|#1\right|} \abs{x} \ge 0
```

---

# Part 2 — Symbols

`\name` → glyph, grouped by atom class. All render upright (roman) unless the
glyph itself carries a style.

## Greek — lowercase

Every ordinary-class symbol — Greek, letterlike, arrows — in one grid:

![Ordinary symbols chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-ordinary.png)

`\alpha` α · `\beta` β · `\gamma` γ · `\delta` δ · `\epsilon` ε ·
`\varepsilon` ε · `\zeta` ζ · `\eta` η · `\theta` θ · `\vartheta` ϑ ·
`\iota` ι · `\kappa` κ · `\lambda` λ · `\mu` μ · `\nu` ν · `\xi` ξ ·
`\pi` π · `\varpi` ϖ · `\rho` ρ · `\sigma` σ · `\varsigma` ς · `\tau` τ ·
`\upsilon` υ · `\phi` φ · `\varphi` φ · `\chi` χ · `\psi` ψ · `\omega` ω ·
`\digamma` ϝ · `\varkappa` ϰ · `\varrho` ϱ

## Greek — uppercase

`\Gamma` Γ · `\Delta` Δ · `\Theta` Θ · `\Lambda` Λ · `\Xi` Ξ · `\Pi` Π ·
`\Sigma` Σ · `\Upsilon` Υ · `\Phi` Φ · `\Psi` Ψ · `\Omega` Ω

## Big operators

![Big operators chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-operators.png)

`\sum` ∑ · `\prod` ∏ · `\coprod` ∐ · `\int` ∫ · `\iint` ∬ · `\iiint` ∭ ·
`\iiiint` ⨌ · `\oint` ∮ · `\oiint` ∯ · `\oiiint` ∰ · `\bigcup` ⋃ ·
`\bigcap` ⋂ · `\bigsqcup` ⨆ · `\biguplus` ⨄ · `\bigvee` ⋁ · `\bigwedge` ⋀ ·
`\bigoplus` ⨁ · `\bigotimes` ⨂ · `\bigodot` ⨀

## Binary operators

![Binary operators chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-binary.png)

`\pm` ± · `\mp` ∓ · `\times` × · `\div` ÷ · `\cdot` ⋅ · `\ast` ∗ ·
`\star` ⋆ · `\circ` ∘ · `\bullet` • · `\diamond` ⋄ · `\cup` ∪ · `\cap` ∩ ·
`\Cup` ⋓ · `\Cap` ⋒ · `\uplus` ⊎ · `\sqcup` ⊔ · `\sqcap` ⊓ ·
`\setminus` ∖ · `\smallsetminus` ∖ · `\wedge` ∧ · `\vee` ∨ · `\land` ∧ ·
`\lor` ∨ · `\oplus` ⊕ · `\ominus` ⊖ · `\otimes` ⊗ · `\oslash` ⊘ ·
`\odot` ⊙ · `\boxplus` ⊞ · `\boxminus` ⊟ · `\boxtimes` ⊠ · `\boxdot` ⊡ ·
`\circledast` ⊛ · `\circledcirc` ⊚ · `\circleddash` ⊝ · `\dagger` † ·
`\ddagger` ‡ · `\amalg` ⨿ · `\wr` ≀ · `\intercal` ⊺ · `\dotplus` ∔ ·
`\divideontimes` ⋇ · `\ltimes` ⋉ · `\rtimes` ⋊ · `\leftthreetimes` ⋋ ·
`\rightthreetimes` ⋌ · `\barwedge` ⊼ · `\veebar` ⊻ · `\doublebarwedge` ⩞ ·
`\curlywedge` ⋏ · `\curlyvee` ⋎ · `\lessdot` ⋖ · `\gtrdot` ⋗ ·
`\triangleleft` ◁ · `\triangleright` ▷ · `\bigtriangleup` △ ·
`\bigtriangledown` ▽

## Relations — equality, order & set

All relation commands (this and the next two sections), as a specimen grid:

![Relations chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-relations.png)

`\leq` / `\le` ≤ · `\geq` / `\ge` ≥ · `\neq` / `\ne` ≠ · `\equiv` ≡ ·
`\approx` ≈ · `\thickapprox` ≈ · `\approxeq` ≊ · `\sim` ∼ · `\thicksim` ∼ ·
`\simeq` ≃ · `\cong` ≅ · `\propto` ∝ · `\asymp` ≍ · `\doteq` ≐ ·
`\doteqdot` ≑ · `\risingdotseq` ≓ · `\fallingdotseq` ≒ · `\eqcirc` ≖ ·
`\circeq` ≗ · `\triangleq` ≜ · `\coloneqq` ≔ · `\eqsim` ≂ · `\backsim` ∽ ·
`\backsimeq` ⋍ · `\bumpeq` ≏ · `\Bumpeq` ≎ · `\ll` ≪ · `\gg` ≫ ·
`\lll` ⋘ · `\ggg` ⋙ · `\leqq` ≦ · `\geqq` ≧ · `\leqslant` ⩽ ·
`\geqslant` ⩾ · `\lesssim` ≲ · `\gtrsim` ≳ · `\lessapprox` ⪅ ·
`\gtrapprox` ⪆ · `\lessgtr` ≶ · `\gtrless` ≷ · `\between` ≬ ·
`\prec` ≺ · `\succ` ≻ · `\preceq` ⪯ · `\succeq` ⪰ · `\precsim` ≾ ·
`\succsim` ≿ · `\subset` ⊂ · `\supset` ⊃ · `\subseteq` ⊆ · `\supseteq` ⊇ ·
`\subseteqq` ⫅ · `\supseteqq` ⫆ · `\Subset` ⋐ · `\Supset` ⋑ ·
`\sqsubset` ⊏ · `\sqsupset` ⊐ · `\sqsubseteq` ⊑ · `\sqsupseteq` ⊒ ·
`\in` ∈ · `\ni` ∋

## Relations — other

`\perp` ⊥ · `\parallel` ∥ · `\shortparallel` ∥ · `\mid` ∣ · `\shortmid` ∣ ·
`\models` ⊨ · `\vDash` ⊨ · `\vdash` ⊢ · `\dashv` ⊣ · `\Vdash` ⊩ ·
`\Vvdash` ⊪ · `\multimap` ⊸ · `\frown` ⌢ · `\smile` ⌣ · `\bowtie` ⋈ ·
`\pitchfork` ⋔ · `\therefore` ∴ · `\because` ∵ · `\gets` ← ·
`\trianglelefteq` ⊴ · `\trianglerighteq` ⊵ · `\vartriangleleft` ⊲ ·
`\vartriangleright` ⊳

## Negated relations

`\notin` ∉ · `\nleq` ≰ · `\ngeq` ≱ · `\nless` ≮ · `\ngtr` ≯ · `\nsim` ≁ ·
`\ncong` ≇ · `\nprec` ⊀ · `\nsucc` ⊁ · `\npreceq` ⋠ · `\nsucceq` ⋡ ·
`\nmid` ∤ · `\nparallel` ∦ · `\nsubseteq` ⊈ · `\nsupseteq` ⊉ ·
`\subsetneq` ⊊ · `\supsetneq` ⊋ · `\subsetneqq` ⫋ · `\supsetneqq` ⫌ ·
`\lneq` ⪇ · `\gneq` ⪈ · `\lneqq` ≨ · `\gneqq` ≩ · `\lnsim` ⋦ · `\gnsim` ⋧ ·
`\precnsim` ⋨ · `\succnsim` ⋩ · `\nvdash` ⊬ · `\nvDash` ⊭ · `\nVdash` ⊮ ·
`\nVDash` ⊯ · `\ntriangleleft` ⋪ · `\ntriangleright` ⋫ ·
`\ntrianglelefteq` ⋬ · `\ntrianglerighteq` ⋭

## Arrows

`\to` / `\rightarrow` → · `\leftarrow` / `\gets` ← · `\leftrightarrow` ↔ ·
`\Rightarrow` ⇒ · `\Leftarrow` ⇐ · `\Leftrightarrow` ⇔ · `\mapsto` ↦ ·
`\mapsfrom` ↤ · `\longrightarrow` ⟶ · `\longleftarrow` ⟵ ·
`\longleftrightarrow` ⟷ · `\Longrightarrow` ⟹ · `\Longleftrightarrow` ⟺ ·
`\longmapsto` ⟼ · `\iff` ⟺ · `\implies` ⟹ · `\impliedby` ⟸ ·
`\uparrow` ↑ · `\downarrow` ↓ · `\updownarrow` ↕ · `\Uparrow` ⇑ ·
`\Downarrow` ⇓ · `\nearrow` ↗ · `\searrow` ↘ · `\swarrow` ↙ · `\nwarrow` ↖ ·
`\hookrightarrow` ↪ · `\hookleftarrow` ↩ · `\twoheadrightarrow` ↠ ·
`\twoheadleftarrow` ↞ · `\rightarrowtail` ↣ · `\leftarrowtail` ↢ ·
`\rightrightarrows` ⇉ · `\leftleftarrows` ⇇ · `\rightleftarrows` ⇄ ·
`\leftrightarrows` ⇆ · `\upuparrows` ⇈ · `\downdownarrows` ⇊ ·
`\Rrightarrow` ⇛ · `\Lleftarrow` ⇚ · `\dashrightarrow` ⇢ · `\dashleftarrow` ⇠ ·
`\rightsquigarrow` / `\leadsto` ⇝ · `\circlearrowright` ↻ ·
`\circlearrowleft` ↺ · `\curvearrowright` ↷ · `\curvearrowleft` ↶ ·
`\looparrowright` ↬ · `\looparrowleft` ↫

Negated arrows: `\nrightarrow` ↛ · `\nleftarrow` ↚ · `\nRightarrow` ⇏ ·
`\nLeftarrow` ⇍ · `\nleftrightarrow` ↮ · `\nLeftrightarrow` ⇎

`\uparrow \downarrow \updownarrow \Uparrow \Downarrow` also serve as stretchy
delimiters inside `\left…\right`.

## Harpoons

`\leftharpoonup` ↼ · `\leftharpoondown` ↽ · `\rightharpoonup` ⇀ ·
`\rightharpoondown` ⇁ · `\upharpoonright` ↾ · `\upharpoonleft` ↿ ·
`\downharpoonright` ⇂ · `\downharpoonleft` ⇃ · `\leftrightharpoons` ⇋ ·
`\rightleftharpoons` ⇌

## Delimiters (as symbols)

![Opening delimiters chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-open.png)

![Closing delimiters chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-close.png)

`\langle` ⟨ · `\rangle` ⟩ · `\lceil` ⌈ · `\rceil` ⌉ · `\lfloor` ⌊ ·
`\rfloor` ⌋ · `\lbrace` { · `\rbrace` } · `\lbrack` [ · `\rbrack` ] ·
`\{` { · `\}` } · `\lvert` | · `\rvert` | · `\vert` | · `\|` ‖ · `\lVert` ‖ ·
`\rVert` ‖ · `\Vert` ‖ · `\backslash` \

## Dots

`\dots` / `\ldots` … · `\cdots` ⋯ · `\vdots` ⋮ · `\ddots` ⋱ ·
`\dotsb` ⋯ · `\dotsc` … · `\dotsm` ⋯ · `\dotsi` ⋯ · `\dotso` …

Ellipses are **Inner** atoms (plain TeX defines them as `\mathinner`), so
they draw a thin space against neighbors on *both* sides — `f(x_1,\ldots,x_n)`
spaces the way the TeXbook sets it. `\vdots` is a plain box: ordinary.

![Inner atoms chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-inner.png)

## Letterlike & ordinary symbols

`\infty` ∞ · `\partial` ∂ · `\nabla` ∇ · `\forall` ∀ · `\exists` ∃ ·
`\nexists` ∄ · `\emptyset` / `\varnothing` ∅ · `\hbar` / `\hslash` ℏ ·
`\ell` ℓ · `\Re` ℜ · `\Im` ℑ · `\aleph` ℵ · `\beth` ℶ · `\gimel` ℷ ·
`\daleth` ℸ · `\eth` ð · `\wp` ℘ · `\prime` ′ · `\backprime` ‵ ·
`\angle` ∠ · `\measuredangle` ∡ · `\sphericalangle` ∢ · `\degree` ° ·
`\neg` / `\lnot` ¬ · `\top` ⊤ · `\bot` ⊥ · `\complement` ∁ · `\surd` √ ·
`\imath` ı · `\jmath` ȷ · `\Bbbk` 𝕜 · `\flat` ♭ · `\sharp` ♯ · `\natural` ♮ ·
`\clubsuit` ♣ · `\diamondsuit` ♢ · `\heartsuit` ♡ · `\spadesuit` ♠ ·
`\triangle` / `\vartriangle` △ · `\triangledown` ▽ · `\square` / `\Box` □ ·
`\blacksquare` ■ · `\Diamond` ◇ · `\lozenge` ◊ · `\blacklozenge` ⧫ ·
`\bigstar` ★ · `\blacktriangle` ▲ · `\blacktriangledown` ▼ ·
`\blacktriangleleft` ◀ · `\blacktriangleright` ▶ · `\checkmark` ✓ ·
`\maltese` ✠ · `\circledR` ® · `\circledS` Ⓢ · `\mho` ℧ · `\Finv` Ⅎ ·
`\Game` ⅁

## Punctuation & literals

![Punctuation chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-punct.png)

`\colon` : · `\$` $ · `\%` % · `\&` & · `\#` #

---

# Part 3 — Function-name operators

![Function-name operators chart](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-functions.png)

Recognized as upright multi-letter operators with correct operator spacing;
`\lim`-family members stack their `_{…}` limits below in display style.

`\sin` `\cos` `\tan` `\cot` `\sec` `\csc` · `\arcsin` `\arccos` `\arctan` ·
`\sinh` `\cosh` `\tanh` `\coth` `\sech` `\csch` · `\log` `\ln` `\lg` `\exp` ·
`\min` `\max` `\sup` `\inf` `\lim` `\limsup` `\liminf` · `\det` `\dim` `\ker`
`\arg` `\gcd` `\deg` `\hom` `\Pr` · `\argmin` `\argmax` · `\mod`

For any operator name not on this list, use `\operatorname{name}` (or
`\operatorname*{name}` for stacked limits).

---

# Part 4 — Not supported (degrades to fallback)

What degradation looks like — unknown commands stay legible, in place:

![Fallback rendering](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-fallback.png)

These parse to an `.unsupported` leaf (host shows its own fallback). See the
"Not yet supported" tail of [COVERAGE.md](COVERAGE.md) for the maintained list.

- `\sideset`, `\mathchoice`, `\DeclareMathOperator` (needs a macro-table branch).
- `\utilde`, harpoon accents (`\overrightharpoon`, …).
- Arbitrarily-tall **extensible delimiter assembly**, and MATH-table variant
  glyphs for `⟨ ⟩ ‖ ⌈ ⌉ ⌊ ⌋` (currently the variant path is gated to
  `( ) [ ] { }`; other delimiters scale continuously).
- `\begin{CD}` commutative diagrams (out of scope — a diagram problem).
- Out of scope by design: `\href`, `\includegraphics`, mhchem `\ce`, siunitx,
  `\verb`.

Caveats on supported commands: `\mathcal` / `\mathscr` / `\mathfrak` render
letters only (no digits); `\mathbf` uses a bold system font rather than a
Mathematical-Alphanumeric codepoint.
