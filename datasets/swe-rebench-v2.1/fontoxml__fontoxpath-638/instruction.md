Problem with `tokenize` or regexs
I ran into this issue when the [`functx:lines` function](http://www.xqueryfunctions.com/xq/functx_lines.html) didn't seem to work for me, giving me an extra blank line after each line.

But I can find a simple reproducer using an example from: https://www.altova.com/xpath-xquery-reference/fn-tokenize which says:

>  For example:
> `fn:tokenize("abracadabra", "(ab)|(a)")` returns `("", "r", "c", "d", "r", "")`

But with fontoxpath:

```js
var fontoxpath = require("fontoxpath")

console.log(fontoxpath.evaluateXPathToStrings(
'fn:tokenize("abracadabra", "(ab)|(a)")',
 null,
undefined,
undefined,
 {language: fontoxpath.evaluateXPath.XQUERY_3_1_LANGUAGE}))
```

Output:

```js
[
  '',          'ab',
  'undefined', 'r',
  'undefined', 'a',
  'c',         'undefined',
  'a',         'd',
  'ab',        'undefined',
  'r',         'undefined',
  'a',         ''
]
```

Looks like the captures are being incorrectly returned as part of the results of `tokenize`.
