Unable to resolve `./foo.ts` to `./foo.d.ts` since 3.9.0
I've dug deeper into https://github.com/un-ts/eslint-plugin-import-x/issues/265 and have found the actual cause which is from this module and/or `oxc-resolver`/`unrs-resolver`.

Last good version: 3.8.7
First bad version: 3.9.0

[Reproduction](https://github.com/silverwind/resolver-bug):

```
git clone https://github.com/silverwind/resolver-bug && cd resolver-bug
npm i eslint-import-resolver-typescript@3.9.0
npx eslint index.js # fails with "error  foo not found in 'mod'  import-x/named"
npm i eslint-import-resolver-typescript@3.8.7
npx eslint index.js # works without error
```

The problem is that `dist/index.d.ts` refers a non-existant `dist/foo.ts`. `dist/foo.d.ts` exists and it seems 3.8.7 and earlier used it.

If possible I'd request for that behaviour to be restored because I can't seem to get my `d.ts` generation to fix this without having to do (expensive) type definition bundling.
