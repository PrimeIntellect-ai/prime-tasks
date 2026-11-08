9.19.0 bug with vue/v-on-event-hyphenation
<!--
  ❗Please don't ignore this template.❗

  If you ignore it, we're just going to respond asking you to fill it out, which wastes everyone's time.
  The more relevant information you can include, the faster we can find the issue and fix it without asking you for more info.
-->

<!--
  Before posting the issue, please confirm that the problem you're getting
  is not related with your code editor configuration.
  To make sure it's not, run: yarn eslint src/your-file.vue
-->

**Checklist**

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have read the [FAQ](https://eslint.vuejs.org/user-guide/#faq) and my problem is not listed.
<!-- If you do not read the FAQ and open an issue that is listed in the FAQ, we may silently close the issue. -->

**Tell us about your environment**

- **ESLint version: 8.54.0**
- **eslint-plugin-vue version: 9.19.0**
- **Node version: 18**
- **Operating System: macOS**

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json5
module.exports = {
  root: true,
  env: {
    node: true
  },
  plugins: ["prettier"],
  extends: [
    "plugin:vue/vue3-recommended",
    "eslint:recommended",
    "@vue/eslint-config-typescript",
    "prettier"
  ],
  rules: {
    "vue/multi-word-component-names": "off",
    "vue/no-reserved-component-names": "off"
  }
};
```

**What did you do?**
Breaks on running `eslint . --fix --ignore-path .gitignore` when the option `plugin:vue/vue3-recommended` or higher is in the .eslintrc.cjs

```
Oops! Something went wrong! :(

ESLint: 8.54.0

Error: .eslintrc.cjs » plugin:vue/vue3-recommended » /Users/electrics01/GitHub/PrivateUploader/frontend/node_modules/eslint-plugin-vue/lib/configs/vue3-strongly-recommended.js:
        Configuration for rule "vue/v-on-event-hyphenation" is invalid:
        Value {"autofix":true} should be equal to one of the allowed values.
```
**Repository to reproduce this issue**
Use any with 9.19.0 and `plugin:vue/vue3-recommended`
