TypeError: Cannot read property 'forEach' of undefined (no-directive-replace)
I'm using `directive` for the first time in a very long time (it is an appropriate use case) and running into the following error:

```text
TypeError: Cannot read property 'forEach' of undefined
    at Object.angular?directive (/aaa/node_modules/eslint-plugin-angular/rules/no-directive-replace.js:56:33)
    at /aaa/node_modules/eslint-plugin-angular/rules/utils/angular-rule.js:234:16
    at Array.forEach (native)
    at callAngularRules (/aaa/node_modules/eslint-plugin-angular/rules/utils/angular-rule.js:228:27)
    at EventEmitter.callBoth (/aaa/node_modules/eslint-plugin-angular/rules/utils/angular-rule.js:86:13)
    at emitOne (events.js:120:20)
    at EventEmitter.emit (events.js:210:7)
    at NodeEventGenerator.applySelector (/aaa/node_modules/eslint/lib/util/node-event-generator.js:265:26)
    at NodeEventGenerator.applySelectors (/aaa/node_modules/eslint/lib/util/node-event-generator.js:294:22)
    at NodeEventGenerator.leaveNode (/aaa/node_modules/eslint/lib/util/node-event-generator.js:317:14)
    at CodePathAnalyzer.leaveNode (/aaa/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:626:23)
    at Traverser.leave (/aaa/node_modules/eslint/lib/linter.js:965:32)
```

The failing line:

```js
[HIDDEN]
  ...
}
```

An inspection of `fnNode.body`: https://gist.github.com/miwillhite/04ac6ccf9abf9bac3ec398e7512adf20

### Additional contract requirements

- The `no-directive-replace` rule must analyze directive callbacks written as concise arrow functions that directly return a directive definition containing `replace`, and report the property using the rule’s existing deprecation diagnostic.
- Analyzing the directive callback form responsible for the reported undefined `.forEach` error must not throw.
