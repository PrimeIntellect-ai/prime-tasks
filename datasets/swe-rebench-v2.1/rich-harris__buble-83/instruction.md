Destructuring assignments in for-of loop heads are not transpiled
Example:

```js
var x; for ({x} of []) {a();}
```

Destructuring variable declarations work, though.
