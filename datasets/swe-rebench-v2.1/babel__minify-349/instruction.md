Number literal minification is suboptimal
Tested in the online repl:

Input:

```js
console.log(11000);
console.log(110000);
```

Expected output:

```js
console.log(11e3),console.log(11e4);
```

Actual output:

```js
console.log(11000),console.log(1.1e5);
```

### Additional contract requirements

- When minifying the existing exponential literal `1e2`, output `1e2` rather than `100`.
