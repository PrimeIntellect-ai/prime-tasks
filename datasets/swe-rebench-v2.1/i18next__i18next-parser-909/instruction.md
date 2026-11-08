Error from JSX spread attributes such as `<a {...props}>`
<!--
Before you submit an issue we recommend you visit [docs](https://www.i18next.com/) or [docs](https://react.i18next.com/) or [docs](https://github.com/i18next/next-i18next) or [StackOverflow](https://stackoverflow.com/search?q=i18next) or similar and ask any questions you have or mention any problems you've had getting started with i18next.

**Please read this entire template before posting any issue. If you ignore these instructions and post an issue here that does not follow the instructions, your issue might be closed, locked.**
-->

## 🐛 Bug Report

Running i18next-parser on a JSX tag that spreads attributes results in the following error.

```
TypeError: Cannot read properties of undefined (reading 'escapedText')
    at file:///Users/josh/src/node_modules/i18next-parser/dist/lexers/jsx-lexer.js:228:51
    at Array.find (<anonymous>)
    at file:///Users/josh/src/node_modules/i18next-parser/dist/lexers/jsx-lexer.js:227:66
    at Array.map (<anonymous>)
    at JsxLexer.parseChildren (file:///Users/josh/src/node_modules/i18next-parser/dist/lexers/jsx-lexer.js:214:7)
    at JsxLexer.nodeToString (file:///Users/josh/src/node_modules/i18next-parser/dist/lexers/jsx-lexer.js:178:41)
    at JsxLexer.jsxExtractor (file:///Users/josh/src/node_modules/i18next-parser/dist/lexers/jsx-lexer.js:144:46)
    at parseTree (file:///Users/josh/src/node_modules/i18next-parser/dist/lexers/jsx-lexer.js:41:41)
    at visitNodes (/Users/josh/src/node_modules/typescript/lib/typescript.js:27937:24)
    at forEachChildInJsxElement (/Users/josh/src/node_modules/typescript/lib/typescript.js:28705:61)```

## To Reproduce

```js
<Trans>Please <a {...hrefProps}>click here.</a></Trans>
```

## Expected behavior

i18next-parser cleanly extracts the translation string.

## Your Environment

- *runtime version*: Node 18.16.1
- *i18next version*: i18next-parser 8.7.0
- *os*: Mac
- *any other relevant information*: This may have been introduced in #862.
