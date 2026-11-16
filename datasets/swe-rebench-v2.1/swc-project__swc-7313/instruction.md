Transform optional chaining maybe incorrectly, inconsistent with babel
### Describe the bug

If a is `undefined`, this code can run in browser directly, and Babel transformed like this:

<img width="488" alt="image" src="https://user-images.githubusercontent.com/57202839/233581829-b08de93f-9d9d-4353-8e6d-1aeb2f4c8e59.png">

SWC output:
(a === null || a === void 0 ? void 0 : a.b())();

Is this an expected behavior

### Input code

```typescript
a?.b()()
```


### Config

```json
{
  "jsc": {
    "transform": {
      "react": {
        "runtime": "automatic"
      }
    },
    "parser": {
      "syntax": "typescript",
      "tsx": true
    },
    "target": "es5",
    "loose": false,
    "minify": {
      "compress": false,
      "mangle": false
    }
  },
  "module": {
    "type": "es6"
  },
  "minify": false,
  "isModule": true
}
```


### Playground link

https://play.swc.rs/?version=1.3.52&code=H4sIAAAAAAAAA0u010vS0NTQ5AIA1MkElQkAAAA%3D&config=H4sIAAAAAAAAA1VQyw6DMAy77ytQzly3w%2F5hHxF1AXWiDyWpNIT497WFMji1tR3b6XLrOviIgWe35Gt%2BKKOXIbA7oAwyodETUKDk1TrKIGDS4FCtgZ1e67n2m2NEFuKzncxe8VtGdY4khm1U6BurUijlRBcbRR6plACS%2B66GKQQpHQachHbMWW%2BH%2BZxngotMIldhkaIfp2P%2B1rrXSHDhnSrZfiZ33eIf8Be1sMMYrLzaZF1i%2FQEQs2upZQEAAA%3D%3D

### Expected behavior

if a is undefined, code can run successfully

### Actual behavior

Output code is `(a === null || a === void 0 ? void 0 : a.b())();`, an Error has been thrownÏ

### Version

1.3.52

### Additional context

_No response_

### Additional contract requirements

- For `a?.b()()`, if `a` is `undefined` or `null`, evaluating the expression must short-circuit without attempting to invoke a value produced by the optional chain, and must not throw.
- For `a?.b()()`, `a?.b()()()`, `a?.b()().c`, `a?.b()()?.c`, and `a?.b()()?.c()()`, preserve the optional-chain short-circuit behavior: a nullish `a` short-circuits the chain, and an optional access such as `?.c` also short-circuits when its receiver is nullish.
