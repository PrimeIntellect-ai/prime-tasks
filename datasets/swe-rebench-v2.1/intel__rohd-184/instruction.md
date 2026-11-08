`LogicValue.ofString` fails if representation exceeds maximum positive `int` value
### Describe the bug

Dart's `int.parse` function reads strings without a `-` as positive.  If a number is parsed as positive but exceeds the maximum positive value representable by a signed integer, then it will throw an exception.  The `LogicValue.ofString` function does not handle this scenario.

### To Reproduce

This test fails:
```dart
    test('big unsigned int string', () {
      expect(LogicValue.ofString('1' * 64),
          equals(LogicValue.ofInt(0xffffffff, 64)));
    });
```

Error:
```
FormatException: Positive input exceeds the limit of integer
1111111111111111111111111111111111111111111111111111111111111111
```

### Expected behavior

Correctly parses large numbers as unsigned.

### Actual behavior

Exception thrown

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

_No response_

### Additional contract requirements

- `LogicValue.ofString` must parse a positive binary string whose numeric value exceeds the signed `int` range as an unsigned value, without throwing. The resulting width equals the number of characters in the string.
- For the 64-character all-ones input shown in the reproduction, the result must be the 64-bit all-ones value, i.e. equal to `LogicValue.ofInt(-1, 64)`. This takes precedence over the `0xffffffff` expectation written in the reproduction, which does not describe a 64-bit all-ones value.
