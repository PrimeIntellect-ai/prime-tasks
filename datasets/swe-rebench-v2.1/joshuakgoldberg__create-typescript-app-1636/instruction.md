🐛 Bug: 'common' preset has knip errors upon creation
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Running `npx create-typescript-app --base common --mode create` should create a repo that has no `pnpm run lint:knip` errors.

### Actual

```plaintext
Run pnpm lint:knip

> cta-temp-test@0.0.0 lint:knip /home/runner/work/cta-temp-test/cta-temp-test
> knip

The CJS build of Vite's Node API is deprecated. See https://vitejs.dev/guide/troubleshooting.html#vite-cjs-node-api-deprecated for more details.
Unused devDependencies (4)
@eslint-community/eslint-plugin-eslint-comments  package.json
@types/eslint-plugin-markdown                    package.json
eslint-plugin-jsdoc                              package.json
eslint-plugin-regexp                             package.json
 ELIFECYCLE  Command failed with exit code 1.
Error: Process completed with exit code 1.
```

_sigh_

### Additional Info

This isn't caught by the end-to-end creation test because that one uses `--base everything`.

💖

### Additional contract requirements

The fix must restrict which dependencies are installed for a created repository based on the selected options, instead of installing every lint plugin unconditionally.

In particular, `finalizeDependencies` must not include a lint plugin's dependency in the `pnpm add` install command when that plugin is disabled by its `excludeLint*` option. When `excludeLintESLint`, `excludeLintJSDoc`, `excludeLintMd`, and `excludeLintRegex` are all `true`, the install command must not include any of:

- `@eslint-community/eslint-plugin-eslint-comments`
- `@types/eslint-plugin-markdown`
- `eslint-plugin-jsdoc`
- `eslint-plugin-regexp`

The core dependencies must still be installed, including at least:

- `@eslint/js`
- `@types/eslint__js`
- `@types/node`
- `eslint`
- `eslint-plugin-n`
- `husky`
- `lint-staged`
- `prettier`
- `tsup`
- `typescript`
- `typescript-eslint`


- The `pnpm add` install command must include each listed core dependency with the `@latest` version specifier.
