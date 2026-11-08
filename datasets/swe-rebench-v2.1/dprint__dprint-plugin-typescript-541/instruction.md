Doesn't remove unnecessary parenthesis
Version: 0.39.0

Input:

```js
const options = { foo: false };
(options).foo = true;
```

Output:
```js
const options = { foo: false };
(options).foo = true;
```

Expected output:

```js
const options = { foo: false };
options.foo = true;
```
