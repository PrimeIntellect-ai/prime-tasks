v1.0.0 regression: "TypeError: Object.defineProperty called on non-object" on certain SVGs
Take this SVG for example:

![](https://rawgit.com/zmwangx/f1e79da72dcc724108840b7d53c158af/raw/36eb4004156a52cdc5cc40005bcf13f6c0000eb9/sample.svg)

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <foreignObject width="100%" height="100%">
    <style>div { color: red; }</style>
    <body xmlns="http://www.w3.org/1999/xhtml"><div>hello, world</div></body>
  </foreignObject>
</svg>
```

This looks like valid SVG to my eyes; it displays fine, and svgo v0.7.2 handles it just fine. However, with svgo v1.0.0:

```console
$ svgo sample.svg
TypeError: Object.defineProperty called on non-object
    at Function.defineProperty (<anonymous>)
    at CSSStyleDeclaration.addStyleHandler (/usr/local/lib/node_modules/svgo/lib/svgo/css-style-declaration.js:36:12)
    at CSSStyleDeclaration.hasStyle (/usr/local/lib/node_modules/svgo/lib/svgo/css-style-declaration.js:26:10)
    at CSSStyleDeclaration.setProperty (/usr/local/lib/node_modules/svgo/lib/svgo/css-style-declaration.js:242:10)
    at Object.fn (/usr/local/lib/node_modules/svgo/plugins/inlineStyles.js:156:34)
    at Object.<anonymous> (/usr/local/lib/node_modules/svgo/node_modules/css-tree/lib/walker/create.js:133:26)
    at List.each (/usr/local/lib/node_modules/svgo/node_modules/css-tree/lib/utils/list.js:143:12)
    at Object.walkDeclarations (/usr/local/lib/node_modules/svgo/node_modules/css-tree/lib/walker/create.js:131:27)
    at Object.walkDeclarations (/usr/local/lib/node_modules/svgo/node_modules/css-tree/lib/walker/create.js:124:34)
    at Object.walkDeclarations (/usr/local/lib/node_modules/svgo/node_modules/css-tree/lib/walker/create.js:285:30)
```

### Additional contract requirements

Processing the example SVG above with the `inlineStyles` plugin must not throw, and the plugin must inline the stylesheet onto the matching element: the `<style>` element is removed and its declaration is applied to the `<div>` as a `style` attribute. With pretty-printing enabled, the optimized output must be exactly:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
    <foreignObject width="100%" height="100%">
        <body xmlns="http://www.w3.org/1999/xhtml">
            <div style="color:red">
                hello, world
            </div>
        </body>
    </foreignObject>
</svg>
```
