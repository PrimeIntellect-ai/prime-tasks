Rule `no-textarea-mustache` cannot difference `<Textarea>` component
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

- **ESLint version:** `^8.24.0`
- **eslint-plugin-vue version:** `^9.5.1`
- **Node version:** `16.17.1`
- **Operating System:** `Windows 10`

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json5
{
  extends: [
    'plugin:vue/vue3-recommended',
    // 'standard',
    // 'plugin:jsonc/recommended-with-jsonc',
    // 'plugin:yml/standard',
    // 'plugin:markdown/recommended',
    '@vue/typescript/recommended'
  ],
  env: {
    es6: true,
    browser: true,
    node: true
  },
  parser: 'vue-eslint-parser',
  parserOptions: {
    ecmaVersion: 'latest'
  },
  reportUnusedDisableDirectives: true
}
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<template>
  <Textarea value="Almost" :max-length="10">
    <template #count="{ value }">
      {{ `${value.length}/10` }}
    </template>
  </Textarea>
</template>
```

**What did you expect to happen?**

No error occurred.

**What actually happened?**
<!--
  Please include the actual, raw output from ESLint.
  If you are only looking at the results of your editor extension, also check the CLI results.
-->

Get a error:

```log
error  Unexpected mustache. Use 'v-model' instead  vue/no-textarea-mustache
```

**Repository to reproduce this issue**
<!--
  ❗ Please share a repository that can reproduce your issue.
  ❗ If you don't share it, we just label it as requesting a repository that can reproduce your issue.
  ❗ If you don't share it for a few days, we silently close this issue.
-->

You can add a valid test in [here](https://github.com/vuejs/eslint-plugin-vue/blob/master/tests/lib/rules/no-textarea-mustache.js#L25):

```json5
{
  filename: 'test.vue',
  code: '<template><div><Textarea>{{text}}</Textarea></div></template>'
}
```

Then test it and it will fail.
