Feature request: handle AggregateErrors
Currently, as far as I can tell, AggregateErrors get serialized like this, no matter what errors they contain:

```
{
  name: 'AggregateError',
  message: '',
  stack: 'AggregateError\n' +
    '    at REPL4:1:24\n' +
    '    at Script.runInThisContext (node:vm:129:12)\n' +
    '    at REPLServer.defaultEval (node:repl:572:29)\n' +
    '    at bound (node:domain:433:15)\n' +
    '    at REPLServer.runBound [as eval] (node:domain:444:12)\n' +
    '    at REPLServer.onLine (node:repl:902:10)\n' +
    '    at REPLServer.emit (node:events:525:35)\n' +
    '    at REPLServer.emit (node:domain:489:12)\n' +
    '    at [_onLine] [as _onLine] (node:internal/readline/interface:422:12)\n' +
    '    at [_line] [as _line] (node:internal/readline/interface:892:18)'
}
```

(This is with Node 18.14.2, but I don't think anything materially different will happen on a different runtime.)

Can the `errors` array get serialized nicely?
