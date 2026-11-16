🚀 Feature: Add getAccessKind
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/ts-api-utils/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

I took a peek through the [typescript-eslint `yarn.lock`](https://github.com/typescript-eslint/typescript-eslint/blob/b615fc295c05599085979e2064c6907645715e21/yarn.lock) to see who depends on `tsutils` still. [`eslint-plugin-deprecation`](https://github.com/gund/eslint-plugin-deprecation) does still for exactly one function: [`import { isReassignmentTarget } from 'tsutils';`](https://github.com/gund/eslint-plugin-deprecation/blob/5a32ce0c761782902c07ec9df4dee5150f7b5c4c/src/rules/deprecation.ts#L22).

[`isReassignmentTarget` is a one-liner in `tsutils`](https://github.com/ajafff/tsutils/blob/03b4df15d14702f9c7a128ac3fae77171778d613/util/util.ts#L1172-L1174) that calls to a [much larger `getAccessKind function`](https://github.com/ajafff/tsutils/blob/03b4df15d14702f9c7a128ac3fae77171778d613/util/util.ts#L1064).

### Additional Info

This is essentially a split-off from #3, long after I'd thought #3 was resolved. 😄

### Additional contract requirements

Expose the named `getAccessKind` utility, together with its `AccessKind` result values, from the library's public entry point. Classify an expression according to its syntactic context as `None` (no access), `Read`, `Write`, `Delete`, or `ReadWrite` (both read and write).
