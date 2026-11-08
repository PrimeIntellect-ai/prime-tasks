Changes in order should cause --fail-on-update to fail
<!--
Before you submit an issue we recommend you visit [docs](https://www.i18next.com/) or [docs](https://react.i18next.com/) or [docs](https://github.com/i18next/next-i18next) or [StackOverflow](https://stackoverflow.com/search?q=i18next) or similar and ask any questions you have or mention any problems you've had getting started with i18next.

**Please read this entire template before posting any issue. If you ignore these instructions and post an issue here that does not follow the instructions, your issue might be closed, locked.**
-->

## 🐛 Bug Report

When the keys are complete but in a wrong order calling `i18next --fail-on-update` with `sort: true` in the config does update the files but not fail.

## To Reproduce

1. Have a project with an unsorted translation file and `sort: true` in the config.
2. Run `i18next --fail-on-update 'src/**/*.{ts,tsx,js,jsx}'`

## Expected behavior

Expected the command to fail, since there are updates in the translation file.

## Your Environment

- *runtime version*: node v20
- *i18next-parser version*: 8.3.0
- *os*: Windows

### Additional contract requirements

- When this happens, the error message must be exactly `Some keys were sorted and failOnUpdate option is enabled. Exiting...`.
