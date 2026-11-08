Calling a private optional chained field fails with TypeError is not a function
### Describe the bug

- [x] I've read [if you think transpilation is wrong](https://github.com/swc-project/swc/issues/7435).

When target is `es2017` (< es2022), the optional chained private field in method `search` becomes `undefined()` causing this runtime error:
```
: _class_private_field_get1.call)(this)

TypeError: (intermediate value)(intermediate value)(intermediate value) is not a function
```

### Input code

```typescript
class Foo {
  #priv
  search() {
    this.#priv?.()
  }
}

console.log(new Foo().search())
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "typescript",
      "tsx": false
    },
    "target": "es2017",
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

https://play.swc.rs/?version=1.3.74&code=H4sIAAAAAAAAA0vOSSwuVnDLz1eo5lJQUC4oyiwD0sWpiUXJGRqaYEEFhZKMzGI9sJy9noYmUKiWq5aLKzk%2Frzg%2FJ1UvJz9dIy%2B1HGSIhqYeTKumAgCEDmZWWwAAAA%3D%3D&config=H4sIAAAAAAAAA1VPSQ7CMAy85xWRzxyAA0j8gUdEwa2Csil2JaKqfydpk0Jv9iye8SykhDdpeMi5jGWJKhGmfS8IZc%2FqUxDgHJF0MpHh1FmmSg3KEq7QsjHAKo3I1YV0PV%2FuzQE2BMLuaJgz3gz5P1MHFxMSHYVVqvxo8ZgoWiq48JpWsv1S%2B24NbvAT9bD9MBh6dienCcXyBZ3DefIXAQAA

### SWC Info output

_No response_

### Expected behavior

I would expect that the function is not invoked:
```js
search() {
  var _class_private_field_get1;
  (_class_private_field_get1 = _class_private_field_get(this, _priv)) === null || _class_private_field_get1 === void 0 ? void 0 : _class_private_field_get1.call(this);
}
```

Related, [tsc](https://www.typescriptlang.org/play?#code/MYGwhgzhAEBiD29oG8BQ1oGIAOAnAlgG7rQQCmYuwAFgBQCUKJGALtfhAHQ4GED8nBiQC+qUamDwAdhHggynEPADmtKWQDucRA07lKNBoyA) generates:
```js
search() {
  var _a;
  (_a = __classPrivateFieldGet(this, _Foo_priv, "f")) === null || _a === void 0 ? void 0 : _a.call(this);
}
```

### Actual behavior

The search method is transpiled as:

```js
search() {
  var _class_private_field_get1;
  ((_class_private_field_get1 = _class_private_field_get(this, _priv)) === null || _class_private_field_get1 === void 0 ? void 0 : _class_private_field_get1.call)(this);
}
```

notice the `_class_private_field_get1.call)(this)`.

### Version

1.3.74

### Additional context

Issue related to private optional chaining: https://github.com/swc-project/swc/issues/3610 (but that issue does not call the property's value)

### Additional contract requirements

- The optional-chaining compilation step is exposed as a public function `optional_chaining(config: Config, unresolved_mark: Mark)` in the module `swc_ecma_transforms_compat::es2020`, where `Config` is the public optional-chaining configuration struct (which implements `Default`). It returns a transformation pass that implements `Fold`.
