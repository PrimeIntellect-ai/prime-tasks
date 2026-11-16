Support new syntax features in ES2019
The following two proposals have arrived at Stage 4.

- [Optional catch binding](https://github.com/tc39/proposal-optional-catch-binding) ... https://github.com/tc39/proposals/commit/83f2325bbf9804052cf371d3fdcd2a9b420715c4
- [JSON superset](https://github.com/tc39/proposal-json-superset) ... https://github.com/tc39/proposals/commit/22c787bf5a7df5453a273ac851716dd8cd4f0a29

We can start to support those in espree and core rules.

Status of upstream:

- ESTree: https://github.com/estree/estree/pull/189
- Acorn: 5.6.0 is released :tada:
- Espree: https://github.com/eslint/espree/pull/380

### Additional contract requirements

- With ES2019 enabled, Espree must accept U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR as literal characters inside string literals, as permitted by the JSON superset proposal.
- Core rules must process those string literals without producing diagnostics solely because either separator occurs inside the literal.
