Add more informative looped connection error message
### Motivation

Might be worth adding a more descriptive looped connection error message. Currently showing `Unhandled exception: LateInitializationError: Field '_preTickSubscription@22087482' has already been initialized.`.

Code:

```dart
import 'package:rohd/rohd.dart';

void main() {
  final a = Logic();
  final b = Logic();

  a <= b;
  b <= a;
}
```

### Desired solution

Add more informative looped connection error message.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- Connecting a `Logic` signal to itself, whether directly or through a cycle of connections, must be rejected by throwing a `SelfConnectingLogicException` instead of allowing the connection to proceed.
- `SelfConnectingLogicException` is a public class available from `package:rohd/src/exceptions/logic/logic_exceptions.dart` and is a subclass of `RohdException`.
- The thrown exception carries the message `Failed to connect signal "$a" with signal "$b": Self connecting logic not allowed.`, where `$a` and `$b` are the `toString()` representations of the source and destination signals involved in the rejected connection.
