Make `LogicValue` comparable
### Motivation

Calling `sort` on a `List<LogicValue>` results in an error since they are not comparable.  We should implement functionality in `LogicValue` so that they can be naturally compared.

If the value is not valid, we should probably just throw an exception (like we do for other number-based operations).

### Desired solution

Make `LogicValue` implement [Comparable](https://api.dart.dev/stable/3.0.2/dart-core/Comparable-class.html)

Throw exception if not valid.

Consider width properly, since we need to use `int` vs `BigInt` depending on size.

### Alternatives considered

Current workaround is to sort based on `toInt()` or `toBigInt()`

### Additional details

_No response_

### Additional contract requirements

- `LogicValue` implements `Comparable<LogicValue>`.
- For valid operands of equal width, comparison orders the unsigned bit-pattern values represented by their fixed-width bits, including values whose highest bit is set.
- `LogicValue` provides a public method `int compareTo(Object other)`.
- `compareTo` throws `InvalidValueOperationException` when either operand is not valid.
- `compareTo` throws `ValueWidthMismatchException` when the operands have different widths.
- `compareTo` throws a generic `Exception` when `other` is not a `LogicValue`.
- `InvalidValueOperationException` and `ValueWidthMismatchException` are available from `package:rohd/src/exceptions/exceptions.dart`.
