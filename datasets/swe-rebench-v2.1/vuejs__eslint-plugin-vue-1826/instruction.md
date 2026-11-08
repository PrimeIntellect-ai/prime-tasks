vue/attribute-hyphenation doesn't work on <slot> element
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

- **ESLint version:** 8.9.0
- **eslint-plugin-vue version:** 8.5.0
- **Node version:** 16.14.0
- **Operating System:** Windows 11 21H1 22000.493 - (WSL) Ubuntu 20.04.3 LTS(Kernel: 5.10.93.2-microsoft-standard-WSL2)

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```js
/* eslint-env node */
module.exports = {
  root: true,
  extends: [
    "plugin:vue/vue3-recommended",
    "eslint:recommended"
  ],
  env: {
    "vue/setup-compiler-macros": true,
  },
};
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<template>
  <div style="color: red;">
    <slot camelCase withValue="foo" :withBind="1" fooBar-BAZ_QuX />
  </div>
</template>
```

**What did you expect to happen?**
I expect warnings like this to appear:
> Attribute 'withVariableBind' must be hyphenated. eslint(vue/attribute-hyphenation)

**What actually happened?**
<!--
  Please include the actual, raw output from ESLint.
  If you are only looking at the results of your editor extension, also check the CLI results.
-->
Nothing happens.

**Repository to reproduce this issue**
<!--
  ❗ Please share a repository that can reproduce your issue.
  ❗ If you don't share it, we just label it as requesting a repository that can reproduce your issue.
  ❗ If you don't share it for a few days, we silently close this issue.
-->
https://github.com/yusufkandemir/eslint-plugin-vue-slot-issue


Might be related to https://github.com/vuejs/eslint-plugin-vue/commit/602d80faad9b6004d040209c41fba68e062891d2

`<slot>` is a native HTML element(_related to Web Components_), but the rule should also run on that, just like it used to do before.
