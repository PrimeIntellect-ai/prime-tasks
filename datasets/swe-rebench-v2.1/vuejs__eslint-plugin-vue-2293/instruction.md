`vue/require-toggle-inside-transition` false negative with whitespace before the element
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

- **ESLint version:** ^8.39.0
- **eslint-plugin-vue version:** ^9.11.0
- **Node version:** v18.15.0
- **Operating System:** macOS 13.5.2

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json5
/* eslint-env node */
module.exports = {
  root: true,
  extends: ["plugin:vue/vue3-essential", "eslint:recommended"],
  parserOptions: {
    ecmaVersion: "latest",
  },
};
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<template>
  <Transition> <div>Hello</div></Transition>
</template>
```

**What did you expect to happen?**
It should show a red wavy warning of [vue/require-toggle-inside-transition](https://eslint.vuejs.org/rules/require-toggle-inside-transition.html) on the VSCode because there is no v-if of v-show.


**What actually happened?**
<!--
  Please include the actual, raw output from ESLint.
  If you are only looking at the results of your editor extension, also check the CLI results.
-->
It doesn't show any red wavy warnings if there are spaces or line breaks before the element.


**Repository to reproduce this issue**
<!--
  ❗ Please share a repository that can reproduce your issue.
  ❗ If you don't share it, we just label it as requesting a repository that can reproduce your issue.
  ❗ If you don't share it for a few days, we silently close this issue.
-->
https://github.com/yoshi-pi/bug-report-vue-require-toggle-inside-transition
