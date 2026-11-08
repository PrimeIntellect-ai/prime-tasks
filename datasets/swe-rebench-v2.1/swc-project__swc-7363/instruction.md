2022-03 Decorator not working in an exported class
### Describe the bug

parse error trying to use decorator in an exported class

### Input code

```typescript
@decorate()
export class Foo {

  @decorate()
  get name() {
    return "hello"
  }

  @decorate()
  sayHi() {
    return "hello"
  }
}

function decorate() {
  return function(target, {kind}) {
    console.log(target, kind)
  }
}
```


### Config

```json
{
    "test": ".*.tsx?$",
    "jsc": {
        "parser": {
            "syntax": "typescript",
            "decorators": true
        },
        "target": "es2020",
        "transform": {
            "decoratorVersion": "2022-03"
        }
    }
}
```


### Playground link

https://play.swc.rs/?version=1.3.56&code=H4sIAAAAAAAAA32OQQrCQAxF93OKT1ctiGfoSrzGMI11cExkJgWl9O6NrVVBMLvkv%2FdJ21GQ7JXqxtH9JlkRki8FBxGMzgHtFwH0pGB%2FtcVS2GTSITOqM6UklZ2mX6n4xzH%2BM8w5DRw0CuNjLvyL3uJafbYfdhgvkbtp6wzCRRLtk%2FRv4gk0a%2F0M7hpWieYAAAA%3D&config=H4sIAAAAAAAAA1WOwQqDMBBE7%2FkK2XMLwUIP%2FYdeew%2B6KSmayO4KDeK%2Fd43V2tvOvJllJlNV8OIGbtWkp4rBESPtWh3OUdxbHZA8IDcUBoHTRltsEjlJxJoQGrGAeeUg5CL7RP3x4V55IHFIcXld27o%2B2wuY%2F7qjJ8rCkTVhwXwZ9KkdO%2FzNXqatueshFGLwWW3vOsZiBb5vzTJ2%2FgCck9nlAgEAAA%3D%3D

### Expected behavior

decorator works, same as in node

```
ts-node src/index.ts
[Function: get name] getter
[Function: sayHi] method
[class Foo] class
hello
hello
```

### Actual behavior

```
SWCRC=true node -r @swc-node/register src/index.ts
/Users/ola/code/swc-jest-example/src/foo.ts:376
@decorate()
^

SyntaxError: Invalid or unexpected token
    at internalCompileFunction (node:internal/vm:73:18)
    at wrapSafe (node:internal/modules/cjs/loader:1176:20)
    at Module._compile (node:internal/modules/cjs/loader:1218:27)
    at Module._compile (/Users/ola/code/swc-jest-example/node_modules/pirates/lib/index.js:136:24)
    at Module._extensions..js (node:internal/modules/cjs/loader:1308:10)
    at Object.newLoader [as .ts] (/Users/ola/code/swc-jest-example/node_modules/pirates/lib/index.js:141:7)
    at Module.load (node:internal/modules/cjs/loader:1117:32)
    at Function.Module._load (node:internal/modules/cjs/loader:958:12)
    at Module.require (node:internal/modules/cjs/loader:1141:19)
    at require (node:internal/modules/cjs/helpers:110:18)

Node.js v18.16.0

```

### Version

1.3.56

### Additional context

_No response_
