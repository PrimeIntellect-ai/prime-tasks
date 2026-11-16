Pages Router generates invalid TypeScript code in `pages.gen.ts` file for numerical routes
Simple reproduction repo: https://github.com/hamlim/invalid-type-identifier-reproduction

### TL;DR:

If you have a route that starts with a number, e.g. `/1234`, the generated code in `pages.gen.ts` will be considered invalid by TypeScript:

```ts
import type { getConfig as 1234Index_getConfig } from './pages/1234/index';
//                         ^ invalid start to an identifier, can't start with a number
```

### Recommendation:

[HIDDEN]

### Additional contract requirements

- Import aliases generated for numerical routes must be valid TypeScript identifiers and must not begin with a digit.
