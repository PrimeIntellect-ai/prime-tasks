🛠 Tooling: Disable n/no-missing-import altogether
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

I realized just now that it's mostly duplicating the work from `import/extensions` + TypeScript. No need for it when we have both of those things already.

### Additional Info

_No response_
🛠 Tooling: Remove eslint-plugin-typescript-sort-keys altogether
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

It's still referenced in the repo. No need for that.

### Additional Info

_No response_

### Additional contract requirements

The repository’s own ESLint configuration and generated ESLint configurations must disable the `n/no-missing-import` rule. Generated ESLint configurations must not register or otherwise reference the `eslint-plugin-typescript-sort-keys` plugin.
