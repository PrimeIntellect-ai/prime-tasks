Support passing argv and env as arguments to convict function
The convict function should accept argv and/or env as arguments instead of relying exclusively on the process.argv and process.env globals. The benefit of adding these arguments is that it makes convict unit-test friendly and it allows convict to be used outside of a cli environment (for example, in an IDE).

Here's the current workaround:

```js
function solitaryConvict(schema, argv, env) {
  const oldArgv = process.argv
  const oldEnv = process.env
  const config = convict(schema)
  process.argv = oldArgv
  process.env = oldEnv
  return config
}
```

While this works, it's quite a crude workaround.

### Additional contract requirements

- `convict(def, opts)` accepts an optional second argument `opts`. `opts.args` is an array of strings used in place of `process.argv.slice(2)`, and `opts.env` is an object mapping environment variable names to values used in place of `process.env`.
- The configuration object returned by `convict` exposes `getArgs()`, which returns the selected argument list (`opts.args` when supplied, otherwise `process.argv.slice(2)`), and `getEnv()`, which returns the selected environment map (`opts.env` when supplied, otherwise `process.env`).
- Configuration properties mapped to command-line arguments are populated from the selected argument list, and properties mapped to environment variables are populated from the selected environment map.
- Supplying an `args` option that is not an array must cause the `convict` call to throw an error rather than silently accepting it.
