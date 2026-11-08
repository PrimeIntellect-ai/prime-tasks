Add a mechanism for generating random `LogicValue`s
### Motivation

`LogicValue` is a useful type since it supports arbitrary width in an efficient representation.  For testing purposes, it might be desirable to generate a random value on a bus of arbitrary width.  The built-in Dart randomization only randomizes up to 2^32, which means users have to invent their own little code snippets to generate random numbers bigger than 32 bits.

### Desired solution

A way to generate large random numbers, especially for `LogicValue`.

One nice option might be to add an `extension` on `Random`.

It might be nice to support both valid values or a mix of valid and invalid values.

It might be nice to support random `BigInt`s as well.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

Expose random `LogicValue` generation as `nextLogicValue({required int width})` on `dart:math`'s `Random`. Each generated value must have exactly the requested width, including widths greater than 32 bits. Repeated calls using the same `Random` instance must produce random values rather than a fixed value.
