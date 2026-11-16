no-return-wrap crash eslint on empty return statement
```js
promise.then(it => {
    return;
});
```
=>
```
Cannot read property 'type' of null
TypeError: Cannot read property 'type' of null
    at EventEmitter.ReturnStatement (/Users/zloirock/wd/static/node_modules/eslint-plugin-promise/rules/no-return-wrap.js:25:28)
    at emitOne (events.js:101:20)
    at EventEmitter.emit (events.js:188:7)
    at NodeEventGenerator.enterNode (/Users/zloirock/wd/static/node_modules/eslint/lib/util/node-event-generator.js:40:22)
    at CodePathAnalyzer.enterNode (/Users/zloirock/wd/static/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:608:23)
    at CommentEventGenerator.enterNode (/Users/zloirock/wd/static/node_modules/eslint/lib/util/comment-event-generator.js:97:23)
    at Controller.enter (/Users/zloirock/wd/static/node_modules/eslint/lib/eslint.js:925:36)
    at Controller.__execute (/Users/zloirock/wd/static/node_modules/eslint/node_modules/estraverse/estraverse.js:397:31)
    at Controller.traverse (/Users/zloirock/wd/static/node_modules/eslint/node_modules/estraverse/estraverse.js:501:28)
    at Controller.Traverser.controller.traverse (/Users/zloirock/wd/static/node_modules/eslint/lib/util/traverser.js:36:33)
```
Latest versions of `eslint-plugin-promise`, `eslint`, `babel-eslint`
