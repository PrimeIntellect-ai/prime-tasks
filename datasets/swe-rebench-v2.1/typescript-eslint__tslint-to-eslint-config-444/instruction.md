eslint-plugin-eslint-config-prettie error
<!--
👋 Hi, thanks for filing an issue on tslint-to-eslint-config! 💖
Please fill out all fields below to ensure your issue is addressed.

If your issue doesn't provide enough info to fully explain or reproduce your bug, it will be closed. 😦
-->

### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 1.0.0-beta
-   ESLint version: 6.8.0
-   Node version: 10.16.0

#### Actual Behavior

![image](https://user-images.githubusercontent.com/9245110/80798720-9eff9180-8bd7-11ea-8d82-cf183ad9d47d.png)

>   Could not import the "eslint-plugin-eslint-config-prettie" module. Do you need to install packages?



I couldn't find eslint-plugin-eslint-config-prettie package on npm

#### Expected Behavior

replace comment successfuly

### Additional contract requirements

- When adding Prettier ESLint extensions, set `extends` to `["prettier", "prettier/@typescript-eslint"]`.
