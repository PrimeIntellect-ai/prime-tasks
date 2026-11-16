BUG: formatting breaks when 1st parameter is an object
### Scenario

create a logger. emit an entry with first parameter as a data object

```javascript
> const log = require('pino')();
undefined
> log.info({}, "foo %s", "bar");
```

### Expect
well formatted log entry
```
{"pid":25540,"hostname":"My-PC","name":"foo","level":30,"time":1480447139327,"msg":"foo bar"}
```

### Found
An Error is thrown
```
TypeError: s.indexOf is not a function
    at countInterp (C:\ws\nodejs\cwt-oapi-util\node_modules\cwt-logger\node_modules\pino\pino.js:378:13)
    at EventEmitter.LOG (C:\ws\nodejs\cwt-oapi-util\node_modules\cwt-logger\node_modules\pino\pino.js:409:11)
    at repl:1:7
    at sigintHandlersWrap (vm.js:22:35)
    at sigintHandlersWrap (vm.js:96:12)
    at ContextifyScript.Script.runInThisContext (vm.js:21:12)
    at REPLServer.defaultEval (repl.js:313:29)
    at bound (domain.js:280:14)
    at REPLServer.runBound [as eval] (domain.js:293:12)
    at REPLServer.<anonymous> (repl.js:513:10)
```


### More info:
version `3.0.2`
does not reproduce with version `2.15.0` (regression)
