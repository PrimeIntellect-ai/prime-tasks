Add optional pre-process callback to the auto-renderer
Hello,
It would be great adding an option for rendering inline math in display style (but not centering it). In MathJax, it suffices to add:

```
<script type="text/x-mathjax-config">
        MathJax.Hub.Register.StartupHook("TeX Jax Ready",function () {
          var TEX = MathJax.InputJax.TeX;
          var PREFILTER = TEX.prefilterMath;
          TEX.Augment({
            prefilterMath: function (math,displaymode,script) {
              math = "\\displaystyle{"+math+"}";
              return PREFILTER.call(TEX,math,displaymode,script);
            }
          });
        });
        </script>
```

Thank you in advance!

### Additional contract requirements

- The auto-renderer exposes a public function `renderMathInElement(element, options)` in module `contrib/auto-render/auto-render.js`. It scans `element` for math delimited by `options.delimiters` and replaces each matched expression with rendered KaTeX markup.
- The `options` object accepts an optional `preProcess` function `(math: string) => string`. It is called with each raw math string before that string is rendered, and the string it returns is the one that gets rendered. When `preProcess` is not supplied, the original math string is rendered. Inline-delimited math can be rendered in display style without being centered or turned into a display block.
