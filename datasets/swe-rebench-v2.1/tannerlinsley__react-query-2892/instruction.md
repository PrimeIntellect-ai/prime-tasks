No exported member "Mutation"
**Describe the bug**
It looks like exports from `mutation.d.ts` are not picked up correctly by TS. Instead a 'no exported member' error is thrown, making explicit typing with `Mutation` and other members impossible. Contrast that with importing `Query` which works fine.

**To Reproduce**
[Repro sandbox here](https://codesandbox.io/s/fervent-leakey-9dt6f?file=/src/index.tsx)

**Expected behavior**
Type for `Mutation` is imported

### Additional contract requirements

- The `Mutation` type must be importable from the same package entry point (`react-query`) that already exports the `Query` type, so consumers can write type annotations such as `Mutation<...>` without a "no exported member" error.
