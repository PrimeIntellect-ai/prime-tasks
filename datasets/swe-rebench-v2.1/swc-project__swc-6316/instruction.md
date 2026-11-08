[Bug]: Unable to use `await` as an identifier in `ExprStmt`
### Describe the bug

SWC fails to transpile `input.js`, which uses `await` as an identifier.

### Input code

```typescript
// input.js
try { await; } catch { console.log("caught"); }
```


### Config

_No response_

### Playground link

https://play.swc.rs/?version=1.3.11&code=H4sIAAAAAAAAA9PXV8jMKygt0csq5iopqlSoVkgsT8wssVaoVUhOLEnOAAok5%2BcV5%2Bek6uXkp2soJSeWpmeUKGkCFQAAP70bcTsAAAA%3D&config=H4sIAAAAAAAAA0WMTQrEIAxG75K1286id5hDBCctFv9IUhgR714tlu7C915ehUMsrBUyshCPS0pU%2FMMKZAOKZZcVTNf6tKEXagYUeScdiiyd%2BZSEJjUQXHRbGSWbQmYSeRHG3T9m66GQfucYKmjJdAc%2F0N7G%2FHPynaLySe0Cj9ke9LUAAAA%3D

### Expected behavior

`input.js` is a valid JavaScript program:
```console
$ d8 input.js
caught
```
so it should be transpiled by SWC.

### Actual behavior

SWC crashes when the `input.js` is given:
<img width="474" alt="image" src="https://user-images.githubusercontent.com/68288688/199188970-db930701-c272-4ccf-9438-db07c8df5958.png">


### Version

1.3.11 (default SWC playground)

### Additional context

_No response_

### Additional contract requirements

- The shown script must transpile successfully as script input, rather than merely parse successfully, and its output must preserve the behavior that the `catch` block logs `caught`.
- For module-mode input consisting of `await`, report the diagnostic `top level await requires target to es2017 or higher and topLevelAwait:true for ecmascript` before `` `await` cannot be used as an identifier in an async context``. Other diagnostics may also be reported.
