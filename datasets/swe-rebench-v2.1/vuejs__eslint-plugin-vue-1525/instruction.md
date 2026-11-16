Incorrect multiline import indent
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

- **ESLint version:** 7.23.0
- **eslint-plugin-vue version:** 7.12.0

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json5
module.exports = {
  extends: [
    'plugin:vue/recommended',
  ],
  plugins: ['vue'],
  rules: {
    'vue/script-indent': ['warn', 4, {
        baseIndent: 1,
        switchCase: 1,
    }],
  },
};
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<script lang="ts">
    import {
        computed, defineComponent, PropType, ref, watch,
    } from '@vue/composition-api';
```

**What did you expect to happen?**
Nothing

**What actually happened?**
`15:1  warning  Expected indentation of 8 spaces but found 4 spaces  vue/script-indent`

Temporary workaround - add 'ImportDeclaration' to `ignores` option of `vue/script-indent` rule.
