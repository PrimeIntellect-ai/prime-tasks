Hang in specific use cases
When I was using Vitest to test my ESLint rules, I encountered a problem where the test cases were hanging for a long time.

When my worker file is written in TypeScript, it hangs. I have tried specifying `tsRunner` as `tsx` and `esbuild-register` but both are the same.

If I write my worker using JavaScript, it works very well.

Here is a minimal reproduction:

https://stackblitz.com/edit/vitest-dev-vitest-ggrsdgek?file=src%2Frules%2Fdummy.ts

### Additional contract requirements

- Add a `node` runner to the `tsRunner` option of `createSyncFn`. It is identified by the public property `TsRunner.Node`, whose value is the string literal `'node'`.
- Export `STRIP_TYPES_DEFAULT_NODE_VERSION` and `STRIP_TYPES_SUPPORTED_NODE_VERSION` as named exports from `synckit`.
- When `tsRunner` is `TsRunner.Node` and the running Node version is lower than `STRIP_TYPES_SUPPORTED_NODE_VERSION`, `createSyncFn` throws an `Error` whose message is `type stripping is not supported in this node version`.
- When the running Node version supports type stripping, selecting `TsRunner.Node` runs the TypeScript worker through the synchronous wrapper using Node's native type stripping.
