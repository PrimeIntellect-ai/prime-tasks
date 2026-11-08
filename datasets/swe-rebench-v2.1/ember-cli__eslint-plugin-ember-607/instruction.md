`require-super-in-init` rule causes build failure with "Cannot read property 'name' of undefined"
Strange problem with `require-super-in-init`

```
- errorMessage: Build Canceled: Broccoli Builder ran into an error with `EslintValidationFilter` plugin. 💥
Cannot read property 'name' of undefined
  - errorType: Build Error
  - location:
    - column: [undefined]
    - file: addon/utils/query-params-filter-mixin-factory.js
    - line: [undefined]
    - treeDir: /Users/d_dovgan/dev/Projects/application/tmp/broccoli_persistent_filtereslint_validation_filter-input_base_path-FlLfiKrr.tmp
  - message: Build Canceled: Broccoli Builder ran into an error with `EslintValidationFilter` plugin. 💥
Cannot read property 'name' of undefined
  - name: Error
  - nodeAnnotation: broccoli-persistent-filter:EslintValidationFilter
  - nodeName: EslintValidationFilter
  - originalErrorMessage: Cannot read property 'name' of undefined
  - stack: TypeError: Cannot read property 'name' of undefined
    at CallExpression.ember.getModuleProperties.find.property (/Users/d_dovgan/dev/Projects/application/node_modules/eslint-plugin-ember/lib/rules/require-super-in-init.js:36:92)
    at Array.find (native)
    at CallExpression (/Users/d_dovgan/dev/Projects/application/node_modules/eslint-plugin-ember/lib/rules/require-super-in-init.js:36:62)
    at listeners.(anonymous function).forEach.listener (/Users/d_dovgan/dev/Projects/application/node_modules/eslint/lib/util/safe-emitter.js:47:58)
    at Array.forEach (<anonymous>)
    at Object.emit (/Users/d_dovgan/dev/Projects/application/node_modules/eslint/lib/util/safe-emitter.js:47:38)
    at NodeEventGenerator.applySelector (/Users/d_dovgan/dev/Projects/application/node_modules/eslint/lib/util/node-event-generator.js:251:26)
    at NodeEventGenerator.applySelectors (/Users/d_dovgan/dev/Projects/application/node_modules/eslint/lib/util/node-event-generator.js:280:22)
    at NodeEventGenerator.enterNode (/Users/d_dovgan/dev/Projects/application/node_modules/eslint/lib/util/node-event-generator.js:294:14)
    at CodePathAnalyzer.enterNode (/Users/d_dovgan/dev/Projects/application/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:608:23)
```

here is small repository with reproduction [link](https://github.com/Sinled/require-super-in-init-bug/blob/master/app/utils/query-params-filter-mixin-factory.js)

build fails when i use object spread,
i can fix build with `object.assign` but it seems that the problem is not in my code?
