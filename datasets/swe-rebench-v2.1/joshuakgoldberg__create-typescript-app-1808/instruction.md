🐛 Bug: `eslint-plugin-regex` referenced instead of `eslint-plugin-regexp`
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

I am currently reading through the docs to see if I can pick up anything new.

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/8404b1dbe654ec90786eabd82a6196c90bf97771/docs/Tooling.md#lint-regex states that:

> [eslint-plugin-regex](https://github.com/gmullerb/eslint-plugin-regex): Detects issues with JavaScript regular expressions, such as potential exponential complexity.

https://github.com/gmullerb/eslint-plugin-regex allows files to be checked against regular expressions, and does not validate regular expressions. https://github.com/ota-meshi/eslint-plugin-regexp is the plugin that validates regular expressions.

### Additional Info

_No response_

### Additional contract requirements

- The lint exclusion CLI flag must be `--exclude-lint-regexp`.
- The corresponding options property must be `excludeLintRegexp`.
- The flag help text must say: `Don't add eslint-plugin-regexp to enforce good practices around regular expressions.`


- In `docs/Tooling.md`, use `eslint-plugin-regexp` as the plugin name and do not use `eslint-plugin-regex`.
