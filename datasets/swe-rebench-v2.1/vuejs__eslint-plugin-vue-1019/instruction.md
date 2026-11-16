`no-reserved-component-names` crash on visiting `component.data`
<!--
  Before posting the issue, please confirm that the problem you're getting
  is not related with your code editor configuration.
  To make sure it's not, run: yarn eslint src/your-file.vue
-->

**Tell us about your environment**
* **ESLint version:**	6.8.0
* **eslint-plugin-vue version:**	6.1.0
* **Node version:**	12.14.0

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```js
module.exports = {
  root: true,
  parser: require.resolve('vue-eslint-parser'),
  parserOptions: {
    parser: 'babel-eslint',
  },
  plugins: ['vue'],
  rules: {
    'vue/no-reserved-component-names': 'error',
  },
};
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<script>
function fn1() {}
function fn2(component) {
  fn1(component.data);
}

export default {};
</script>
```

**What did you expect to happen?**


**What actually happened?**
<!-- Please include the actual, raw output from ESLint. -->

ESLint crashed.

```text
TypeError: Cannot read property 'type' of undefined
Occurred while linting path/to/vue-file.vue:86
    at Object.unwrapTypes (<CWD>node_modules\eslint-plugin-vue\lib\utils\index.js:827:17)
    at CallExpression > MemberExpression > Identifier[name='component'] (<CWD>node_modules\eslint-plugin-vue\lib\rules\no-reserved-component-names.js:92:38)
    at listeners.(anonymous function).forEach.listener (<CWD>node_modules\eslint\lib\linter\safe-emitter.js:45:58)
    at Array.forEach (<anonymous>)
```
