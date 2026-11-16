problem with parsing text with mixed $$ and $ delimiters
> Before reporting a bug
- [x] Check [common issues](https://katex.org/docs/issues.html).
- [x] Check the bug is reproducible in [the demo](https://katex.org). If not, check KaTeX is up-to-date and installed correctly.
- [x] Search for [existing issues](https://github.com/KaTeX/KaTeX/issues).

**Describe the bug:**
In LaTeX source texts it is common to see inline math like `$x$$y$` which is equivalent to `$xy$`
mixed with display math.

However, such math does not render correctly with the autorender extension, when the delimiter option is set to
```
{delimiters: [
  {left: '$$', right: '$$', display: true},
  {left: '$', right: '$', display: false},
  {left: '\\(', right: '\\)', display: false},
  {left: '\\[', right: '\\]', display: true}
]}
```

**To Reproduce:**
Steps to reproduce the behavior:

display this file in a supported browser
```html
<!DOCTYPE html>
<!-- KaTeX requires the use of the HTML5 doctype. Without it, KaTeX may not render properly -->
<html>
  <head>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/katex.min.css" integrity="sha384-AfEj0r4/OFrOo5t7NnNe46zW/tFg\
W6x/bCJG8FqQCEo3+Aro6EYUG4+cU+KJWu/X" crossorigin="anonymous">

    <!-- The loading of KaTeX is deferred to speed up page rendering -->
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/katex.min.js" integrity="sha384-g7c+Jr9ZivxKLnZTDUhnkOnsh30B4H0rpLUpJ4j\
AIKs4fnJI+sEnkvrMWph2EDg4" crossorigin="anonymous"></script>

    <!-- To automatically render math in text elements, include the auto-render extension: -->
    <script defer
    src="https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/contrib/auto-render.min.js"
    integrity="sha384-mll67QQFJfxn0IYznZYonOWZ644AWYC+Pt2cHqMaRhXVrursRwvLnLaebdGIlYNa"
            crossorigin="anonymous" onload="renderMathInElement(document.body, {delimiters: [
  {left: '$$', right: '$$', display: true},
  {left: '$', right: '$', display: false},
  {left: '\\(', right: '\\)', display: false},
  {left: '\\[', right: '\\]', display: true}
]});"></script>
  </head>
  <body>
    <h1>A note on discrete $$\mathcal{R}$$ symmetries in $\mathbb{Z}$$_{6}$-II orbifolds with Wilson lines</h1>

  </body>
</html>
```

**Expected behavior:**
both the display math and the inline math should be rendered. It is not, but the `$$` in the middle of  `$\mathbb{Z}$$_{6}$` disappears.

Omitting the `$$` (which is a NOOP) in the middle results in correct rendering.
Introducing a space `$\mathbb{Z}$ $_{6}$` also renders the inline math, albeit with a gratuitous space.


**Screenshots:**
![katex-autorender](https://user-images.githubusercontent.com/766159/93270138-af22a280-f76d-11ea-85de-e2f06b7efa83.png)

**Environment (please complete the following information):**
 - KaTeX Version: v0.12.0
 - Device: Linux desktop
 - OS: Fedora 32
 - Browser: Chrome
 - Version: 85.0.4183.102 (Official Build) (64-bit)


**Additional Context:**

We use KaTeX for rendering in a large repository of scientific papers. We don't control the TeX source, and hence can't avoid this mix of delimiters.
