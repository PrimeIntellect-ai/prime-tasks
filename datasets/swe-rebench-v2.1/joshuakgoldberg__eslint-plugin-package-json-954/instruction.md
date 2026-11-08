🚀 Feature: Bring in a require-engines rule
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Following #42 -> #51: we've resolved to create a standalone `require-engines` rule. It should enforce that the field exists in the `package.json` file.


### Additional Info

💖

### Additional contract requirements

- The rule is exposed as `require-engines` in the plugin's rules collection.
- When the `engines` property is absent, the rule reports an error whose message id is `missing`.
