Invalid parse arguments for max-line-length
<!--
👋 Hi, thanks for filing an issue on tslint-to-eslint-config! 💖
Please fill out all fields below to ensure your issue is addressed.

If your issue doesn't provide enough info to fully explain or reproduce your bug, it will be closed. 😦
-->

### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.2.6
-   ESLint version: 6.5.0
-   Node version: 10.16.3

#### Actual Behavior

<!-- What is the behavior right now? -->
I was develop the max-line-length converter but in end-to-end test I was identify that not converting TSLint arguments to ESLint for this rule. I found the solution but I am submiting this bug for track PR. Sorry for that.

#### Expected Behavior

<!-- What are the specific changes you'd like to see? -->
Convert all TSLint arguments in ESLint arguments for max-line-length.

#### Reproduction

<!--
Please paste a link to a repository, Gist, or other means of reproducing your error here.
Note that `tslint-to-eslint-config` includes information from `package.json`, `tsconfig.json`, and other files, so just your ESLint configuration may not be enough.
-->
