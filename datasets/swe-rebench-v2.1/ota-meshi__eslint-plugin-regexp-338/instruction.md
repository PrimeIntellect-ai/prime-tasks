`sort-flags` should autofix flags that's a string literal
**Information:**
- ESLint version: 7.32.0
- `eslint-plugin-regexp` version: 1.3.0

**Description**

`/a/us` is fixable, but `RegExp('a', 'us')` is not.
