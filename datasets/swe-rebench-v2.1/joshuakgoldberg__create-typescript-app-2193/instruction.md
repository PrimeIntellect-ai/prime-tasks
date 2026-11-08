🚀 Feature: Add `ignores` Addon for `blockMarkdownlint`
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Coming over from https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/pull/993#discussion_r2034081595: running `npx create-typescript-app` shouldn't remove any custom user entries in the `.markdownlintignore`.

### Additional Info

🎁

### Additional contract requirements

- When generating files, preserve custom entries already present in `.markdownlintignore`.
- The `blockMarkdownlint` `ignores` add-on must allow additional ignore patterns to appear in the generated ignore file.
