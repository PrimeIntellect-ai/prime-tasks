@typescript-eslint/tslint-eslint-plugin isn't suggested for installation when necessary
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.6.0
-   ESLint version: N/A
-   Node version: N/A

#### Actual Behavior

If you run `tslint-to-eslint-config` on a `tslint.json` with unrecognized rules, you might get a message like:

```
...
⚡ 6 packages are required for running with ESLint. ⚡
  npm install @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint eslint-plugin-import eslint-plugin-jsdoc eslint-plugin-prefer-arrow --save-dev
```

#### Expected Behavior

It should be 7 packages, with the addition of `@typescript-eslint/tslint-eslint-plugin`.

#### Reproduction

https://github.com/KingDarBoja/sample-tslint-to-eslint-comment

This was introduced in #405. 😁
