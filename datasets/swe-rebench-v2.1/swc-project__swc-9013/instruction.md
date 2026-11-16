minifier: invalid index access evaluation of string represented with surrogate pairs
### Describe the bug

Each surrogate character should be regarded as an individual character.

### Input code

```typescript
console.log('💖'[0]);
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
      "compress": {
        "arguments": false,
        "arrows": true,
        "booleans": true,
        "booleans_as_integers": false,
        "collapse_vars": true,
        "comparisons": true,
        "computed_props": true,
        "conditionals": true,
        "dead_code": true,
        "directives": true,
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
        "switches": true,
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
        "unused": true,
        "const_to_let": true,
        "pristine_globals": true
      },
      "mangle": {
        "toplevel": false,
        "keep_classnames": false,
        "keep_fnames": false,
        "keep_private_props": false,
        "ie8": false,
        "safari10": false
      }
    }
  },
  "module": {
    "type": "commonjs"
  },
  "minify": false,
  "isModule": true
}
```


### Playground link (or link to the minimal reproduction)

https://play.swc.rs/?version=1.5.24&code=H4sIAAAAAAAAA0vOzyvOz0nVy8lP11D%2FMH%2FSNPVog1hNawCrbVbhFwAAAA%3D%3D&config=H4sIAAAAAAAAA42VzW7bMAyA732KwOcdtsOAYg%2Bw255BUCzKUSaJhkilCYq8%2B2jFTtOGNnYJYn78ESmSen%2FZ7boj9d2v3bv8lY%2FRFoJy%2FxYJXTLbs0g66JOlvoSRu28LPdKEvI0ETXS9kY5tGYCbFf2c1buISLCoz7IUcvCXx4A9prEA0YNMpOKvJshMn%2B1nVvBtAlzqo3yPGMHmDWIsmZAZBiia4x5jtCOBOdmieJlOaksg1EJMsDI4MxYcVZ5d4IBZYj5TB9aZHh0oKBToOZxAM5NYYpZJ0lPyadjBvg5Du%2BQv1nCysVpWYsK5XYmcVvF6wEBsfM1aCW9wpQY3OBf3q2XwpgDXkp%2Ftjhjyyp38BZAKREuUbQLNb9Pw0k9r1n7TMmQvLcsXhUt%2Fa1lmGKSoJgSvVHaqDBQO2m0WcLWHqbK9dpwZr5SPggMD3kuvKK7pLXB%2F0ILyZQT0CpD7tV7rqhsw9ylc4dNAbODfkiXrDTZrJMuHdUqXtMe4ESABH9BtKMhVMK7jIlviPK7zmh1Ia4BTVSo18LwEZAAYTWzL8qk3ZDzEoxki7j%2FWxKxwvS%2FhZPPQ5v1hXzKOEU4Q19r4P0Zkk8rZTlNXL5P9NL3wqjWllcELP75%2FejMklZfltyXVJXT1IaHWk9NbIi2UMB%2Bp%2B9Bcno97pC7Qn8W8Vev6D4dGmLPmBgAA

### SWC Info output

_No response_

### Expected behavior

```javascript
console.log("\uD83D");
```

### Actual behavior

```javascript
console.log("\uD83D\uDC96");
```

### Version

1.5.24

### Additional context

_No response_
