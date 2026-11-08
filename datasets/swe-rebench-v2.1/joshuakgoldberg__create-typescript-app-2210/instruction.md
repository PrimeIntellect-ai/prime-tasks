🚀 Feature: Use eslint-plugin-yml's standard config over recommended
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

This repo's `eslint.config.js` & `blockESLintYML.ts` set up [eslint-plugin-yml](https://ota-meshi.github.io/eslint-plugin-yml/) with:

https://github.com/bingo-examples/created-typescript-app-everything/blob/ac6c526317195f1e4563dbefc85d836e1f56998a/eslint.config.js#L74

But, the plugin has a "standard" config that enables a few more rules than just "recommended": https://ota-meshi.github.io/eslint-plugin-yml/user-guide/#new-config-eslint-config-js / https://ota-meshi.github.io/eslint-plugin-yml/rules. I'd like to onboard to that.

### Additional Info

This is separate from #2208. That issue is about simplifying the config's `rules` object, and the three currently explicitly enabled rules aren't in the "standard" config.

🎁
