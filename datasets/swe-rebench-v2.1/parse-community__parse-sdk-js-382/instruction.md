Fail to clone object with relation
How to reproduce:

```
$ npm i -g parse
/path/to/lib
└─┬ parse@1.9.2
  └─┬ babel-runtime@6.18.0
    ├── core-js@2.4.1
    └── regenerator-runtime@0.9.6

$ node
> Parse = require('parse/node')
{ ... }
> o = Parse.Object.fromJSON({objectId: '7777777777', className: "Foo", aRelation: {__type: "Relation", className: "Foo"}})
ParseObject { _objCount: 0, className: 'Foo', id: '7777777777' }
> o2 = o.clone()
ParseObject { _objCount: 1, className: 'Foo' }
> o2.relation('aRelation')
Error: Internal Error. Relation retrieved from two different Objects.
    at ParseRelation.value (/path/to/node_modules/parse/lib/node/ParseRelation.js:70:19)
    at ParseObject.value (/path/to/node_modules/parse/lib/node/ParseObject.js:630:15)
    at repl:1:4
    at REPLServer.defaultEval (repl.js:272:27)
    at bound (domain.js:280:14)
    at REPLServer.runBound [as eval] (domain.js:293:12)
    at REPLServer.<anonymous> (repl.js:441:10)
    at emitOne (events.js:101:20)
    at REPLServer.emit (events.js:188:7)
    at REPLServer.Interface._onLine (readline.js:219:10)
```

I'll send PR later.
