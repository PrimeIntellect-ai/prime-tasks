TypeError: [[rawConfiguration.extends],[reportedConfiguration.extends]].flat is not a function
<!--
👋 Hi, thanks for filing an issue on tslint-to-eslint-config! 💖
Please fill out all fields below to ensure your issue is addressed.

If your issue doesn't provide enough info to fully explain or reproduce your bug, it will be closed. 😦
-->

### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.2.11
-   TSLint version: 5.18.0
-   ESLint version: none?
-   Node version: 10.17.0

#### Actual Behavior

<!-- What is the behavior right now? -->

1. I generated an empty angular project with `ng new`, `ng 8.1.3`.
2. I updated manually tslint from 5.15 to 5.18 since this is the minimum required version
3. Then I ran `npx tslint-to-eslint-config` and expected it to migrate from tslint to eslint

But I got this error:

```
npx: installed 41 in 3.972s
❌ 1 error running tslint-to-eslint: ❌
TypeError: [[rawConfiguration.extends],[reportedConfiguration.extends]].flat is not a function
    at exports.findTSLintConfiguration (/home/user/.npm/_npx/19151/lib/node_modules/tslint-to-eslint-config/src/input/findTSLintConfiguration.js:22:10)
    at process._tickCallback (internal/process/next_tick.js:68:7)
```

#### Expected Behavior

<!-- What are the specific changes you'd like to see? -->
I'd expected it to migrate to `eslint` smoothly.

#### Reproduction

<!--
Please paste a link to a repository, Gist, or other means of reproducing your error here.
Note that `tslint-to-eslint-config` includes information from `package.json`, `tsconfig.json`, and other files, so just your ESLint configuration may not be enough.
-->
`tslint-to-eslint-config` is empty.
