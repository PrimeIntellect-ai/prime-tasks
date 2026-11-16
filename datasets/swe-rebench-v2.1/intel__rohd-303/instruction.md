Port can be initialized with empty name
### Describe the bug

Port of the Module can be initialized with empty name.

### To Reproduce

```dart
// system verilog generate: input logic ,
final signal1 = addInput('', unamedSignal);

```

### Expected behavior

throw exception on empty string port initialization

### Actual behavior

The initialization passed and the generated system verilog contains errors.

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

_No response_
