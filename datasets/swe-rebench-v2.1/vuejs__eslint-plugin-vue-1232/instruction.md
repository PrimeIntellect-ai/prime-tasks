crash when using the vue/no-empty-component-block rule on a .js file
<!--
  Before posting the issue, please confirm that the problem you're getting
  is not related with your code editor configuration.
  To make sure it's not, run: yarn eslint src/your-file.vue
-->

**Tell us about your environment**
* **ESLint version:** 7.3.1
* **eslint-plugin-vue version:** 7.0.0-alpha.8
* **Node version:**	v12.18.2

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```js
{
  root: true,

  parserOptions: {
    sourceType: 'module'
  },

  env: {
    browser: true,
    node: true,
    es2020: true
  },

  extends: ['plugin:vue/vue3-recommended'],

  rules: [
    // *other rules*
    'vue/no-empty-component-block': 'error'
  ]
}
```

**What did you do?**
I launched the linter for the .js file

**What did you expect to happen?**
plugin works

**What actually happened?**
```
Oops! Something went wrong! :(

ESLint: 7.3.1

TypeError: Error while loading rule 'vue/no-empty-component-block': Cannot read property 'children' of null
Occurred while linting C:\Users\danyadev\Desktop\vk-desktop\src\components\auth\index.js
    at Object.create (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint-plugin-vue\lib\rules\no-empty-component-block.js:75:7)
    at createRuleListeners (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:758:21)
    at C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:928:31
    at Array.forEach (<anonymous>)
    at runRules (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:873:34)
    at Linter._verifyWithoutProcessors (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:1170:31)
    at Linter._verifyWithConfigArray (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:1268:21)
    at Linter.verify (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:1223:25)
    at Linter.verifyAndFix (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\linter\linter.js:1413:29)
    at verifyText (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\cli-engine\cli-engine.js:224:48)
    at CLIEngine.executeOnFiles (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\cli-engine\cli-engine.js:788:28)
    at ESLint.lintFiles (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\eslint\eslint.js:515:23)
    at Object.execute (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\lib\cli.js:294:36)
    at main (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\bin\eslint.js:142:52)
    at Object.<anonymous> (C:\Users\danyadev\Desktop\vk-desktop\node_modules\eslint\bin\eslint.js:146:2)
    at Module._compile (internal/modules/cjs/loader.js:1138:30)
```

### Additional contract requirements

- The `vue/padding-line-between-blocks` rule must also work without crashing when linting a file that is not a Vue SFC.
- The public `ParserServices` interface declared in `typings/eslint-plugin-vue/util-types/parser-services.ts` exposes a method `getDocumentFragment` whose declared return type is `VDocumentFragment | null`. The declared return type must include `null`, because the method yields no document fragment when the linted file is not a Vue SFC.
