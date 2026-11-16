Exit code is not properly set when template compilation failed
- Maizzle Version: 4.8.4
- Node.js Version: 18.19.0

Hello,

I find that the exit code will be set to zero even if there is an compilation failure across templates:

Log:
```
$ maizzle build production
✖ Failed to compile template: promotional.html
⚠ [components] <x-notExist> could not find notExist.html in the defined root paths (src/components, src/layouts, src/templates)
✔ Built 0 templates in 0.16s
✨  Done in 0.74s.
```
When I echo the exit code, it is zero.

I followed the #986, however the error code is always zero regardless of which `config.build.fail` I choose (verbose, silent or unset). I would like Maizzle to fail so the CI can detect it.

Thanks so much for the help!

### Additional contract requirements

- The public build API is `Maizzle.build(env, config)`. It returns a Promise that resolves to an object containing the generated `files`, and rejects with an `Error` when a template cannot be rendered.
- The `maizzle build <env>` command exits with a non-zero status when a template cannot be rendered, so CI can detect the failure.
- When `build.fail` is set to `silent` or `verbose`, the build continues past rendering failures instead of failing.
