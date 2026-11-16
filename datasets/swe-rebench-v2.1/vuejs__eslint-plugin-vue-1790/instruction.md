no-unused-properties: Misses v-bind inside "style" section (with repro)
**Checklist**

- [+] I have tried restarting my IDE and the issue persists.
- [+] I have read the [FAQ](https://eslint.vuejs.org/user-guide/#faq) and my problem is not listed.

**Tell us about your environment**

- **ESLint version:** ^6.7.2
- **eslint-plugin-vue version:** ^7.0.0
- **Node version:** 14.18
- **Operating System:** Windows 10

**Please show your full configuration:**

See:
https://github.com/ilyub/repro-vue-no-unused-properties/blob/master/.eslintrc.js

```json5
rules: {
    "vue/no-unused-components": "warn",
    "vue/no-unused-properties": "warn",
  },
```

**What did you do?**

See:
https://github.com/ilyub/repro-vue-no-unused-properties/blob/master/src/components/HelloWorld.vue

```vue
<template>
...
</template>

<script lang="ts">
export default defineComponent({
  name: "HelloWorld",
  props: {
    msg: String,
    background: String,
    otherProp: String,
  },
});
</script>

<style scoped lang="scss">
h3 {
  background: v-bind(background);
}
</style>
```

**What did you expect to happen?**

One error: from otherProp.

**What actually happened?**

Two errors: from otherProp and background.

Note that background is used in "style" section.

IMPORTANT NOTE:
Bug occurs in the presense of "vue/no-unused-components".
If you disable it then you get one error as expected.

**Repository to reproduce this issue**

https://github.com/ilyub/repro-vue-no-unused-properties
