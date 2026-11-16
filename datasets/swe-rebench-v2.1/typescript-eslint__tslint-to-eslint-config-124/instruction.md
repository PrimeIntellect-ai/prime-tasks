Consider TSLint rules enabled by eslint-plugin-tslint
### 🚀 Feature Request

ESLint configurations might already enable TSLint rules under [eslint-plugin-tslint](https://github.com/typescript-eslint/typescript-eslint/tree/master/packages/eslint-plugin-tslint).

#### Existing Behavior

Only `tslint.json` is considered as a source of truth.

#### Change Proposal

When creating the list of enabled TSLint rules, apply any rules listed under `eslint-plugin-tslint` on top of `tslint.json` rules.

Related: #5, #34.

### Additional contract requirements

- Add a public function `mergeLintConfigurations(eslint: ESLintConfiguration | Error, tslint: TSLintConfiguration): TSLintConfiguration` in module `src/input/mergeLintConfigurations.ts`.
  - If `eslint` is an `Error`, it returns `tslint` unchanged.
  - If `eslint.rules["@typescript-eslint/tslint/config"]` is missing, or its first element is `"off"`, it returns `tslint` unchanged.
  - Otherwise it returns a new configuration whose `rules` are `tslint.rules` overridden by the `rules` property of the second element of the mapped ESLint rule, preserving the other `tslint` fields.
