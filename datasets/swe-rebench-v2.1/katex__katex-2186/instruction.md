\right{...} causes circular structure in error reporting
**Describe the bug:**
Testing on `katex.org`, here is a minimal bad example based on #2174:
```latex
\newcommand{\myright}[1]{\right{#1}}
\cos\left(x\myright)
```
Error:
> Converting circular structure to JSON --> starting at object with constructor 't' | property 'settings' -> object with constructor 't' | property 'macros' -> object with constructor 'Object' | ... | property 'loc' -> object with constructor 't' --- property 'lexer' closes the circle

**Expected behavior:**
Unless I'm missing something, `\myright` should behave like `\right`.

**Additional context:**
The following code works fine, so it has to do with macro arguments.
```latex
\newcommand{\myright}{\right}
\cos\left(x\myright)
```
Perhaps #2085 fixes this bug, but I haven't checked. If so, we should add a test.

### Additional contract requirements

- The parse-error messages for invalid delimiters must be exactly:
- `Invalid delimiter '1' after '\bigl' at position 7: \bigl 1̲ + 2 \bigr`
- `Invalid delimiter '=' after '\bigr' at position 15: \bigl(1+2\bigr=̲3`
- `Invalid delimiter type 'ordgroup' at position 6: \bigl{̲(̲}̲1+2\bigr)3`
- `Invalid delimiter type 'ordgroup' at position 15: \bigl(1+2\bigr{̲)̲}̲3`
