Missing parenthesis for new with an arrow function
```js
new (() => {});
```

outputs

```js
new () => {};
```

which is invalid. I'm not sure if this can even result into a meaningful result, but it parses in Chrome at least.

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22new%20(()%20%3D%3E%20%7B%7D)%3B%22%2C%22options%22%3A%7B%22printWidth%22%3A80%2C%22tabWidth%22%3A2%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Afalse%2C%22bracketSpacing%22%3Atrue%7D%7D

### Additional contract requirements

- Formatting `var n = new async function() {\n}();` must produce `var n = new (async function() {\n})();`; formatting `var n = new async function() {\n  await 1;\n}();` must produce `var n = new (async function() {\n  await 1;\n})();`.
- Formatting `new (function() {});` must produce `new (function() {\n})();`.
