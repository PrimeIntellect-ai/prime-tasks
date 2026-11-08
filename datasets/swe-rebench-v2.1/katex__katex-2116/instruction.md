\cal support
KaTeX supports the new-style `\mathcal{...}` but not the old-style `{\cal ...}` font format.  We should ideally support both, as we do for `\rm`/`\mathrm` etc.; see the [support table](https://katex.org/docs/supported.html#style-color-size-and-font).

This oversight was recently mentioned to me by the author of a project using KaTeX as a common issue with KaTeX where they needed to fall back to MathJax, so I think it's relevant to the real world.

### Additional contract requirements

- `\cal` is a prefix command that takes no explicit arguments and applies the calligraphic font to the material that follows, rendering it equivalently to `\mathcal{...}`.
