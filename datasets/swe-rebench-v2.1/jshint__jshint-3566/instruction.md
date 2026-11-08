`"` and `\"` are considered as different keys
JsHint version: 2.9.6

Code:
```
var x = {
  '"': 10,
  '\"': 20,
};
```

Configuration: default

Result: no warnings

Expected result: W075: Duplicate key

### Additional contract requirements

- Report the warning at line 3, column 7 with the exact message `Duplicate key '"'.`
