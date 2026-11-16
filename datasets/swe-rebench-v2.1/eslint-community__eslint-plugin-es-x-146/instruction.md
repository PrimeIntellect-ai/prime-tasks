Add rule for RegExp duplicate named capture groups (ES2025)
https://github.com/tc39/proposal-duplicate-named-capturing-groups

### Additional contract requirements

- Provide the rule under the module name `no-regexp-duplicate-named-capturing-groups`.
- Report the error with the exact message `ES2025 RegExp duplicate named capturing groups are forbidden.` For a regex literal, locate the error at the first repeated named capture group (column 10 in `/(?<x>a)|(?<x>b)/` and column 18 in `/(?<x>a)|(?<y>b)|(?<x>c)/`). For a `new RegExp(...)` expression, locate the error at the start of the expression (column 1).
