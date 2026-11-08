es5 will generate illegal js code
### Describe the bug

swc generates illegal js code when i use input code

### Input code

```typescript
async function a(fn) {
    (await fn()).a = "123";
}
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "ecmascript",
      "jsx": false
    },
    "target": "es5",
    "loose": false,
    "minify": {
      "compress": false,
      "mangle": false
    }
  },
  "module": {
    "type": "commonjs"
  },
  "minify": false,
  "isModule": true
}
```


### Playground link

https://play.swc.rs/?version=1.3.76&code=H4sIAAAAAAAAA0ssrsxLVkgrzUsuyczPU0jUSMvTVKjmUgACjcTyxMwShbQ8DU1NvUQFWwVDa65aANML9EIwAAAA&config=H4sIAAAAAAAAA1WPSw7DIAxE95wCed1tN71DD2FRJwLxEyZSUZS7Fyikzc4z8%2ByRdyElGFbwkHsdq4iYmNKpq8PFZ3xXB0g5ZJV0zHCbqeEWLWiZunV8E8iYVsp9i%2B8DBxsC08SH57TXS%2FkvVMHFRMxXsKHoV0vXOjEqwYXX1sPxSC6xqXbNBW8YfuRsPK%2BD5udcz2kjcXwAmJf30BkBAAA%3D

### Expected behavior

correctly transpile `await` in left hand side of assignment expressions

### Actual behavior

``` javascript
function a(fn) {
    return _a.apply(this, arguments);
}
function _a() {
    _a = _async_to_generator(function(fn) {
        return _ts_generator(this, function(_state) {
            (yield fn()).a = 1; // cannot use yield in ordinary functions
            return [
                2
            ];
        });
    });
    return _a.apply(this, arguments);
}
```

### Version

1.3.76

### Additional context

_No response_
