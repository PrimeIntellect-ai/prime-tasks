TypeError: Cannot read property 'length' of undefined
<!--
👋 Hi, thanks for filing an issue on tslint-to-eslint-config! 💖
Please fill out all fields below to ensure your issue is addressed.

If your issue doesn't provide enough info to fully explain or reproduce your bug, it will be closed. 😦
-->

### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.1.7
-   ESLint version: n/a
-   Node version: v11.15.0

#### Actual Behavior

```
❌ 1 error running tslint-to-eslint: ❌
TypeError: Cannot read property 'length' of undefined
    at formatRuleArguments (/usr/local/share/powershell/Modules/nvm/2.3.0/vs/v11.15.0/lib/node_modules/tslint-to-eslint-config/src/creation/formatMissingRules.js:19:28)
    at Object.exports.formatMissingRules (/usr/local/share/powershell/Modules/nvm/2.3.0/vs/v11.15.0/lib/node_modules/tslint-to-eslint-config/src/creation/formatMissingRules.js:7:36)
    at Object.exports.formatConvertedRules (/usr/local/share/powershell/Modules/nvm/2.3.0/vs/v11.15.0/lib/node_modules/tslint-to-eslint-config/src/creation/formatConvertedRules.js:11:75)
    at exports.writeConversionResults (/usr/local/share/powershell/Modules/nvm/2.3.0/vs/v11.15.0/lib/node_modules/tslint-to-eslint-config/src/creation/writeConversionResults.js:18:39)
    at exports.convertConfig (/usr/local/share/powershell/Modules/nvm/2.3.0/vs/v11.15.0/lib/node_modules/tslint-to-eslint-config/src/conversion/convertConfig.js:10:24)
    at processTicksAndRejections (internal/process/task_queues.js:86:5)
```
#### Expected Behavior

Not throw error

#### Reproduction

<!--
Please paste a link to a repository, Gist, or other means of reproducing your error here.
Note that `tslint-to-eslint-config` includes information from `package.json`, `tsconfig.json`, and other files, so just your ESLint configuration may not be enough.
-->

Ran it in this repo https://github.com/sourcegraph/eslint-config referencing the tslint.json from https://github.com/sourcegraph/tslint-config

### Additional contract requirements

A TSLint rule whose configuration omits its argument list must still be formatted without throwing.
