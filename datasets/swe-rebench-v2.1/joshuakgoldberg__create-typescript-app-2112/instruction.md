🐛 Bug: eslint.config.js used with ESM even if package type is `"commonjs"`
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If a repo defines `"type": "commonjs"` in its `package.json`, then the ESLint config should either be `eslint.config.mjs` or use CJS.

### Actual

It's still printed as `eslint.config.js` with ESM.

### Additional Info

Example: https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#r2025645674

### Additional contract requirements

- The shared options include an optional `type` field whose value is `"commonjs"` or `"module"`. When it is absent, the type defaults to `"module"` for new projects and to the existing `package.json` value for existing repositories.
- The generated `package.json` includes a top-level `"type"` field set to the package type.
- For a `commonjs` package, the generated ESLint config must use `files: ["**/*.{js,mjs,ts}"]`.
- When transitioning an existing repository, the ESLint config files removed are `eslint.config.{cjs,js}` for a `commonjs` package and `eslint.config.{cjs,mjs}` otherwise.
