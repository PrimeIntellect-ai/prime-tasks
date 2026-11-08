a tap subtest is breaking all following subtests in file
Side-sprout (to keep in line with pino's natural theme) of issue #208: there is a dormant issue in one of pino's test suites, which can reproduced as follow:
* edit `test/levels.test.js` to move the test 'level-change even' anywhere else than at the bottom of the file
* run full test suite with `npm run test` or just the relevant test suite with: `./node_modules/.bin/tap test/levels.test.js`
* all subsequent tests to fail with:
```
    not ok XX - test after end() was called # time=7.746ms
      ---
      stack: |
        EventEmitter.handle (test/levels.test.js:12:7)
        EventEmitter.setLevelVal (pino.js:125:12)
        EventEmitter._setLevel (pino.js:163:17)
        EventEmitter.applyOptions (lib/tools.js:43:8)
        EventEmitter.Pino (pino.js:104:22)
        pino (pino.js:91:16)
        Test.<anonymous> (test/levels.test.js:52:18)
        loop (node_modules/function-loop/index.js:35:15)
      at:
```

Looks like the 'level-change even' test is able to damage pino's or tap's state permanently, meaning there is a bug somewhere.
