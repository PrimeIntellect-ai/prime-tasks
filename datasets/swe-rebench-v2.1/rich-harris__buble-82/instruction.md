Destructured catch parameters are not transpiled
[Spec](https://tc39.github.io/ecma262/#prod-CatchParameter). Example:
```js
try {} catch ({message}) {}
```

### Additional contract requirements

- For the example, transpilation must produce `try {} catch (ref) {` with `var message = ref.message;` in the catch body.
