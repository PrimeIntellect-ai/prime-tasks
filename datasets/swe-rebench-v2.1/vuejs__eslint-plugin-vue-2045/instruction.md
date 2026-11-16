vue/attribute-hyphenation changes original code which would break app
<!--
  Before posting the issue, please confirm that the problem you're getting
  is not related with your code editor configuration.
  To make sure it's not, run: yarn eslint src/your-file.vue
-->

**Tell us about your environment**
* **ESLint version:** 5.16.0
* **eslint-plugin-vue version:** 5.2.3
* **Node version:**	10.14.2

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```js
// https://eslint.org/docs/user-guide/configuring

module.exports = {
  root: true,
  parserOptions: {
    parser: 'babel-eslint'
  },
  env: {
    browser: true
  },
  extends: ['plugin:vue/essential'],
  // required to lint *.vue files
  plugins: ['vue'],
  // add your custom rules here
  rules: {
    // 'vue/prop-name-casing': ['error', 'camelCase']
    'vue/attribute-hyphenation': 'error'
  }
}
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<!-- HelloWorld/index.vue-->
<template>
  <div class="HelloWorld">
    <TestPara
      :AttrEe="4"
      :attr_ff="5"
      :attr_Gg="6"
      :Attr_Hh="7"
      :_attr_ii="8"
      :_attr_Jj="9"
      :_attrKk="10"
      :_AttrLl="11"
    />
  </div>
</template>

<script>
import TestPara from './TestPara'
export default {
  name: 'HelloWorld',
  components: {
    TestPara
  }
}
</script>
```
```vue
<template>
  <div class="TestPara"></div>
</template>

<script>
<!-- HelloWorld/TestPara.vue-->
export default {
  name: 'TestPara',
  props: [
    'AttrEe',
    'attr_ff',
    'attr_Gg',
    'Attr_Hh',
    '_attr_ii',
    '_attr_Jj',
    '_attrKk',
    '_AttrLl'
  ],
  created () {
    window.vm = this
    console.log(vm.$props)
  }
}
</script>
```
run

```bash
cd .\vue\vue-prop-parse\
npx eslint .\src\components\HelloWorld\index.vue --fix
```
**What did you expect to happen?**

I can still access all the `$props` in the `TestPara` with the **valid value** without changing the code in the `TestPara`.

**What actually happened?**
<!-- Please include the actual, raw output from ESLint. -->
```vue
<!-- HelloWorld/index.vue-->
<template>
  <div class="HelloWorld">
    <TestPara
      :attr-ee="4"
      :attr_ff="5"
      :attr-gg="6"
      :attr-hh="7"
      :_attr_ii="8"
      :-attr-jj="9"
      :-attr-kk="10"
      :-attr-ll="11"
    />
  </div>
</template>

<script>
import TestPara from './TestPara'
export default {
  name: 'HelloWorld',
  components: {
    TestPara
  }
}
</script>

```
After lint, I got the error at the console with

> '-attr-jj' is not a valid attribute name.

And `Attr_Hh`, `attr_Gg`, `_AttrLl`, `_attrKk`, `_attr_Jj` in $props are `undefined`. I check the [test cases](https://github.com/vuejs/eslint-plugin-vue/blob/master/tests/lib/rules/attribute-hyphenation.js) and find you didn't consider these situations like `_` in the attributes name.

In this case, I thought you shouldn't try to fix the original code? Because that would break the app down.

What do you think?

### Additional contract requirements

- When the autofix applies to an attribute whose name contains an underscore, the attribute name must stay unchanged, so the component keeps receiving the same prop value.
