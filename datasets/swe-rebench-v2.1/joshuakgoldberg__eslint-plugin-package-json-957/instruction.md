🚀 Feature: unify import of recommended config with other plugins
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

I would like to import your plugin and use its recommended config like in [other](https://github.com/sindresorhus/eslint-plugin-unicorn#recommended-config) [ESLint](https://github.com/azat-io/eslint-plugin-perfectionist#flat-config-eslintconfigjs-1) [plugins](https://github.com/jsx-eslint/eslint-plugin-react#flat-configs):

```js
import packageJson from 'eslint-plugin-package-json';

export default [
  packageJson.configs.recommended,
];
```

But I get an error `Cannot read properties of undefined (reading 'recommended')`.

Was there any special reason to do things differently than [ESLint recommends](https://eslint.org/docs/latest/extend/plugin-migration-flat-config#migrating-configs-for-flat-config)?

### Additional Info

_No response_
