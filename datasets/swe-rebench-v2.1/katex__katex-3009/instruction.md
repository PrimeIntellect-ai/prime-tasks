Too strict about accents in math mode
> Before reporting a bug
- [x] Check [common issues](https://katex.org/docs/issues.html).
- [x] Check the bug is reproducible in [the demo](https://katex.org). If not, check KaTeX is up-to-date and installed correctly.
- [x] Search for [existing issues](https://github.com/KaTeX/KaTeX/issues).

**Describe the bug:**
Does not admit `\mathrm{\AA}` even in non-strict. It's a bad idea, but current LaTeX takes it fine.

**(La)TeX code:**
The code of (La)TeX you tried to render:
```latex
\mathrm{\AA}
```

**Expected behavior:**
Should get the Å sign with warnings. LaTeX on overleaf will complain a bit, tell me about how it's hoping that replacing `\accent` with `\mathaccent` will work out, but it does work out.

**Screenshots:**
```
KaTeX parse error: Can't use function '\r' in math mode at position 1: \̲r̲ ̲A
```

**Environment (please complete the following information):**
 - KaTeX Version: 0.13.5
 - Device: Desktop
 - OS: Windows 10
 - Browser: Cr
 - Version: 90

**Additional context:**
Part of #2876. Not something I would normally write, since Unicode feels better and `\text` is a thing.

The parse error is honestly a bit hard to get, since it's complaining about the result of macro expansion.

### Additional contract requirements

- When parsing `\'echec` in math mode with strict mode set to `error`, the error message must be exactly `LaTeX-incompatible input and strict mode is set to 'error': LaTeX's accent \' works only in text mode [mathVsTextAccents]`.
- In non-strict math mode, `\mathrm{\AA}` must build successfully and produce the same output as `\mathrm{\r A}` (the Å sign), and must emit a warning.
