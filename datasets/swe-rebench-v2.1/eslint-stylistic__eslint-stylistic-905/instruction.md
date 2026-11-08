`no-extra-parens`: `v5.2.0` broke `nestedBinaryExpressions: false` for TypeScript
### Validations

- [x] Follow our [Code of Conduct](https://github.com/eslint-stylistic/eslint-stylistic/blob/main/CODE_OF_CONDUCT.md)
- [x] Read the [Contributing Guide](https://eslint.style/contribute/guide).
- [x] Check that there isn't already an issue that reports the same bug to avoid creating a duplicate.

### Describe the bug

After upgrading to `v5.2.0`, `nestedBinaryExpressions: false` no longer works for TypeScript.
Looks like it's introduced by PR https://github.com/eslint-stylistic/eslint-stylistic/pull/873
<img width="816" height="347" alt="Image" src="https://github.com/user-attachments/assets/8caa0267-8983-41d3-9de6-99802f2207ba" />

### Reproduction

See above

### Contributes

- [ ] I am willing to submit a PR to fix this issue
- [ ] I am willing to submit a PR with failing tests

### Additional contract requirements

- With `options: ['all', { nestedBinaryExpressions: false }]`, the following TypeScript input must produce no `unexpected` diagnostic (the parentheses around the nested intersection type are allowed):

```ts
type Foo = boolean | (Bar & Baz)
```
