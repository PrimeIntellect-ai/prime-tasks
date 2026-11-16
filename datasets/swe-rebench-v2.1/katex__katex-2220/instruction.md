Display mode doesn't work for MathML output
**Describe the bug:**
Display mode does not work for MathML output (it does for HTML output).

**To Reproduce:**
Render any expression, using the options `{displayMode: true, output: 'mathml'}`.
See [JSFiddle](https://jsfiddle.net/2b497Ls0/).

**Expected behavior:**
Expression renders in display mode, i.e.&nbsp;display-style math centred on its own line.

**Actual behavior:**
Expression appears to render in inline mode.

**Screenshot:**
<img src="https://user-images.githubusercontent.com/48375680/77227660-cfa5e180-6bbc-11ea-9d99-977e65fff34a.png" width="300px">

**Environment:**
 - KaTeX Version: 0.11.1
 - Browser: any browser which supports MathML

### Additional contract requirements

- When rendering an expression with `{displayMode: true, output: 'mathml'}`, the generated `<math>` element must carry the attribute `display="block"`. When `displayMode` is false, the `<math>` element must not carry `display="block"`, so the MathML stays in its default inline form.
