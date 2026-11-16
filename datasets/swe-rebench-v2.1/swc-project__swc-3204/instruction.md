if_return returns unreachable code
### Describe the bug

see example

### Input code

```typescript
const IndexPage = () => {
  if (value === "loading") {
    return 1;
  } else if (value === "error") {
    return 2;
  } else {
    return 3;
  }
  return 4;
};
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "ecmascript",
      "jsx": false
    },
    "target": "es2019",
    "loose": false,
    "minify": {
      "compress": {
        "arguments": false,
        "arrows": true,
        "booleans": true,
        "booleans_as_integers": false,
        "collapse_vars": true,
        "comparisons": true,
        "computed_props": false,
        "conditionals": false,
        "dead_code": false,
        "directives": false,
        "drop_console": false,
        "drop_debugger": true,
        "evaluate": true,
        "expression": false,
        "hoist_funs": false,
        "hoist_props": true,
        "hoist_vars": false,
        "if_return": true,
        "join_vars": true,
        "keep_classnames": false,
        "keep_fargs": true,
        "keep_fnames": false,
        "keep_infinity": false,
        "loops": true,
        "negate_iife": true,
        "properties": true,
        "reduce_funcs": false,
        "reduce_vars": false,
        "side_effects": true,
        "switches": false,
        "typeofs": true,
        "unsafe": false,
        "unsafe_arrows": false,
        "unsafe_comps": false,
        "unsafe_Function": false,
        "unsafe_math": false,
        "unsafe_symbols": false,
        "unsafe_methods": false,
        "unsafe_proto": false,
        "unsafe_regexp": false,
        "unsafe_undefined": false,
        "unused": true
      },
      "toplevel": true,
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

https://play.swc.rs/?version=1.2.124&code=H4sIAAAAAAAAA0vOzysuUfDMS0mtCEhMT1WwVdDQVLC1U6jmUlDITFPQKEvMKQWK2toqKOXkJ6Zk5qUraYIlFRSKUktKi%2FIUDK2BvFqF1JziVHQdqUVF%2BUXo6o2Q1KNIGIMluOB8E2uuWmsAX3KG16AAAAA%3D&config=H4sIAAAAAAAAA22TTbLbIAzH7%2BJ1Fm0Xnek7QHc9A0NAOLwCYpDIiyeTu1fYDraT7tCPv4S%2BuA%2BfZIaP%2B5B1ISjtRFNifRs%2BBjBRkyk%2B83ASmSCnA8HjNLAuI3CT0I9v33%2FJdUAkWAWnIfrk3dSCGYy5AFE7i1ONkJi6TpeCX2JyqWKdEQPo9GYrTconhhHK5mowBJ0J1FWX7tFe08UTpgOqDFblgnnvnqxnj0nMDi1oqwzarRDrCxj2V9iJJI6IEklyR2jhXMexNXF5Gq46VM3Q7dvcCnm0%2B13QEytXE72gNdvFcUFLoavKO1WAa0lPzSf6dOjFXwDJM2iipOMu%2F5k7mcVR6f6j8snJIHnqVKa8ZZVglOKU965X2LKGwh66qICtBlqFZgu%2BwkNB5C0ocE7a3Z3py7O57LLiKQO6fi9t024bwmKq51IdaduDN%2Fhb0uL9PFYeNV9eGU3xjOEtRAS%2BoH3D0gnGV1hkhW%2F5ldZkQfoMdndRqZmtyvbbMAe4QniWHXUa%2B%2B49RBDR1gbuc4Pmb%2FlzeGzf8Lkz9GcVzoH%2FAau%2FxYX7AwAA

### Expected behavior

```js
const IndexPage = ()=>"loading" === value ? 1 : "error" === value ? 2 : 3;
```

### Actual behavior

```js
const IndexPage = ()=>"loading" === value ? 1 : "error" === value ? 2 : 4;
```

### Version

1.2.124

### Additional context

_No response_

### Additional contract requirements

For the shown function, when `value` is neither `"loading"` nor `"error"`, minification must preserve the fallback result `3`. The unreachable trailing `return 4` must not change the value returned for that case.
