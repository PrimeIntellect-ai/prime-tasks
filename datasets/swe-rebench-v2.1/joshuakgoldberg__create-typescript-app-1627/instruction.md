🚀 Feature: Bring in @vitest/eslint-plugin to replace eslint-plugin-vitest
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

https://github.com/vitest-dev/eslint-plugin-vitest exists now & is going to be regularly updated! Hooray! Time to switch from `eslint-plugin-vitest` to it.

### Additional Info

💖

### Additional contract requirements

- The generated ESLint configuration imports the Vitest plugin from `@vitest/eslint-plugin` (replacing `eslint-plugin-vitest`), with that import placed immediately after the `@eslint-community/eslint-plugin-eslint-comments/configs` import and before the `eslint-plugin-jsdoc` import.
- The dependency installation includes `@vitest/eslint-plugin` (replacing `eslint-plugin-vitest`) when test tooling is not excluded.
