rule consistent-output crashing when invalid tests array has missing element.
test case:
```js
// invalid
invalid: [
  {code:"foo"},
  ,
  {code: "bar"}
]
```

error:
```bash
TypeError: Cannot read property 'type' of null
    at testRun.invalid.filter.testCase (C:\repo\eslint\node_modules\eslint-plugin-eslint-plugin\lib\rules\consistent-output.js:36:7
6)
    at Array.filter (native)
    at Program.utils.getTestInfo.forEach.testRun (C:\repo\eslint\node_modules\eslint-plugin-eslint-plugin\lib\rules\consistent-outp
ut.js:36:49)
    at Array.forEach (native)
    at EventEmitter.Program (C:\repo\eslint\node_modules\eslint-plugin-eslint-plugin\lib\rules\consistent-output.js:32:41)
    at emitOne (events.js:120:20)
    at EventEmitter.emit (events.js:210:7)
    at NodeEventGenerator.applySelector (C:\repo\eslint\lib\util\node-event-generator.js:265:26)
    at NodeEventGenerator.applySelectors (C:\repo\eslint\lib\util\node-event-generator.js:294:22)
    at NodeEventGenerator.enterNode (C:\repo\eslint\lib\util\node-event-generator.js:308:14)
```

### Additional contract requirements

- When `utils.getTestInfo` processes `var foo = new bar.RuleTester; foo.run(bar, baz, { valid: [,], invalid: [bar, , baz] })`, it must exclude missing array elements from the counts and produce `{ valid: 0, invalid: 2 }`.
- Linting a RuleTester run whose invalid test array contains a missing element must complete without throwing.
