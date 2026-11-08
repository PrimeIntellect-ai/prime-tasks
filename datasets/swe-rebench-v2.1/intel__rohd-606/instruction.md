toRadixString() fails on LogicValue.zero
### Describe the bug

[HIDDEN]

### To Reproduce

 LogicValue.zero.zeroExtend(32).toRadixString() fails with a bad array access.

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

- For a zero-valued `LogicValue`, `toRadixString()` must not throw and must return a valid representation with a `0` digit. The unpadded representation must contain exactly one digit.
