`LogicValue.ofRadixString` returns 0 for invalid inputs
### Describe the bug

If you call `LogicValue.ofRadixString("something")` it returns `LogicValue.zero`.  It should instead throw a `LogicValueConstructionException`.

### To Reproduce

_No response_

### Expected behavior

_No response_

### Actual behavior

_No response_

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

```yaml

```

### Additional: Context

_No response_

### Additional contract requirements

- A length/radix literal whose digit field is empty (for example `"10'b"`) is
  well-formed. `LogicValue.ofRadixString` returns a `LogicValue` of the
  specified length whose bits are all zero, so
  `LogicValue.ofRadixString("10'b")` equals `LogicValue.ofInt(0, 10)`.
