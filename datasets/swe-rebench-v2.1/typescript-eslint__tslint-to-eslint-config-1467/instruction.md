Default to ESLint's `root: true` to match TSLint behavior
<!--
👋 Hi, thanks for filing an issue on tslint-to-eslint-config! 💖
Please fill out all fields below to ensure your issue is addressed.

If your issue doesn't provide enough info to fully explain your proposed feature, it will be closed. 😦
-->

### 🚀 Feature Request

To the best of my knowledge, tslint [does not](https://palantir.github.io/tslint/usage/configuration/) automatically search for and process `tslint.json` files that are in parent directories. ESLint does this by default, and needs to [be disabled by](https://eslint.org/docs/user-guide/configuring/configuration-files#using-configuration-files) specifying `root: true` at the configuration top-level. To match the default behavior of tslint, we could set this ESLint top-level property

If this feature request is accepted, I am able to make a PR

I can make a PR

#### Existing Behavior

Does not set `root` property of ESLint configuration

#### Change Proposal

Set top-level `root` to `true` in all generated configs
