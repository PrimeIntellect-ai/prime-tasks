🐛 Bug: Add options.bin to ESLint allowDefaultProject
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If someone specifies a `bin` entry in their `package.json` that isn't in `src/`, then it will need to use `parserOptions.projectService.allowDefaultProject` to be linted. It should be mentioned alongside `"*.config.*s"` in the generated `eslint.config.js`

### Actual

Nothing does that right now:

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/aaf2d6536de8a2ff862c132cad5e2351a9ebe923/src/steps/writing/creation/createESLintConfig.ts#L83

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/b180d182713dea5dc1f995a8b2a7731a757455c0/src/next/blocks/blockESLint.ts#L104

### Additional Info

Prototyped in #1839.

💖
