Strange "can't read property webppl" error msg with wrong data type in inference args
When you (incorrectly) write the samples arg in inference opts as a string, you get:

```
Cannot read property 'webppl' of undefined
```

Minimal example

```
Infer({method: 'MCMC', samples: '5000'}, function(){return flip(0.5)});
```

### Additional contract requirements

- Passing `samples` as a string must not surface the misleading
  `Cannot read property 'webppl' of undefined` error.

- Error handling must work for errors thrown from deeply nested JavaScript
  function calls. When the captured V8 stack trace contains no frame that
  corresponds to webppl code, recovering the stack must not fail with the
  confusing `Cannot read property 'webppl' of undefined` error. Instead, the
  captured JavaScript frames are retained in the recovered stack. Each retained
  JavaScript frame has `webppl: false` and `name: null`, and its `fileName` is
  the JavaScript source file containing the corresponding call site.
