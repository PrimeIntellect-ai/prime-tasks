TypeError: roleValue.toLowerCase is not a function in role-has-required-aria-props
Where the `role` attribute is data driven, the linter explodes because it's expecting a string and tried to do `.toLowerCase()`

I have `<div :role="ariaRole"></div>` which is eventually a string, but the linter sees it as a Node.

```
TypeError: roleValue.toLowerCase is not a function
Occurred while linting /Users/gavynmckenzie/dev/bbm/patterns/src/components/molecules/Modal/MModal.vue:55
    at EventEmitter.VElement (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vuejs-accessibility/src/rules/role-has-required-aria-props.js:38:12)
    at EventEmitter.emit (events.js:203:15)
    at NodeEventGenerator.applySelector (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:3276:26)
    at NodeEventGenerator.applySelectors (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:3290:22)
    at NodeEventGenerator.enterNode (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:3298:14)
    at traverse (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:113:13)
    at traverse (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:120:21)
    at traverse (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:120:21)
    at traverse (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:120:21)
    at traverseNodes (/Users/gavynmckenzie/dev/bbm/patterns/node_modules/eslint-plugin-vue/node_modules/vue-eslint-parser/index.js:131:5)
```
