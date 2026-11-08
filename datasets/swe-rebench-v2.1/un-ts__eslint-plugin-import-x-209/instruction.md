Replacing the built-in default import resolver that supports `exports` and `imports` from `package.json`
`eslint-plugin-import-x` has `eslint-import-resolver-node` as a dependency. When no resolver is specified in the eslint config, the `eslint-import-resolver-node` will be used. However, `eslint-import-resolver-node` doesn't support `exports` and `imports` from `package.json` and @ljharb ~~simply refuses~~ doesn't have time to implement this feature and even locks the feature request issue, see https://github.com/import-js/eslint-plugin-import/issues/1810.

So our plan is to abandon the `eslint-import-resolver-node`. We will be building a new eslint import resolver upon ~~[`@dual-bundle/import-meta-resolve`](https://www.npmjs.com/package/@dual-bundle/import-meta-resolve)~~ [`enhanced-resolve`](https://www.npmjs.com/package/enhanced-resolve). We will ship it with `eslint-plugin-import-x` and it will be an interface v3-only resolver.

In the next major version of `eslint-plugin-import-x`, we will remove `eslint-import-resolver-node` in favor of our own default resolver.

### Additional contract requirements

- `src/node-resolver.ts` exports a factory `createNodeResolver(options?)` that returns an ESLint import-resolver v3 object.
- The returned resolver exposes `interfaceVersion` equal to `3`, a non-empty descriptive `name` string, and a `resolve(modulePath: string, sourceFile: string)` method.
- `resolve` returns an object `{ found: boolean, path?: string | null }`. It returns `found: true` with an absolute `path` when a concrete file is located, `found: true` with `path: null` for Node built-in modules and for `data:` URLs, and `found: false` when resolution fails.
- The factory accepts an optional options object. `extensions` (default `['.mjs', '.cjs', '.js', '.json', '.node']`) sets the file extensions tried when resolving, and `conditionNames` (default `['default', 'module', 'import', 'require']`) sets the conditions used when reading a package's `exports` map.
