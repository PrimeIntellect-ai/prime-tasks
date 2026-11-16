[Question] The behavior of importsField conflicts with `require.resolve`
For the [out of package scope of importField](https://github.com/webpack/enhanced-resolve/blob/main/test/importsField.js#L1214) example, there are some inconsistencies between `require.resolve` and `enhanced-resolve`.

Executing `require.resolve('#b')` in the importsField folder will report an error directly:

<img width="1193" alt="image" src="https://user-images.githubusercontent.com/30187863/169676352-db069fd3-c1d2-4c88-a508-eb194f681a3b.png">

> node version: 12.22.10

But the above test case is executed normally.

So, should we add [HIDDEN]?

### Additional contract requirements

- Provide a public function `checkImportsExportsFieldTarget(relativePath)` exported from `lib/util/path.js`. It accepts a relative module request path (a string) as used in an `imports` or `exports` field.
- It returns an `Error` whose message matches "Trying to access out of package scope" when the path attempts to traverse outside the package scope (for example, when `..` segments escape the package root).
- It returns `undefined` when the target is safe, i.e. it stays within the package boundaries.
- Resolving a request through the `imports` field whose target escapes the package scope must fail with an error whose message matches "Trying to access out of package scope".
