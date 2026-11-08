loadTSConfig assume valid JSON
**Describe the bug**

The `loadTSConfig` function assumes `tsconfig.json` is JSON, however, `tsconfig.json` officially is a JSONC file, which allows for comments.

From: https://www.typescriptlang.org/docs/handbook/declaration-files/dts-from-js.html#tsconfig

> The TSConfig is a jsonc file ...

https://github.com/oclif/core/blob/7aec22efe81948780e78486080f494c9e108f74c/src/config/ts-node.ts#L18-L45

Fails with:

> Warning: Could not parse tsconfig.json for .... Falling back to compiled source.

**To Reproduce**

- Add a comment to `tsconfig.json`
- Run a command

**Expected behavior**

Allow comments.

**Screenshots**

N/A
