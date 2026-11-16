Implement `neq`
## Motivation
Equality checks with `eq` are simple, but you have to use `~...eq` for not-equal-to.  It would be nice to be able to do not-equal-to using `neq`.

## Desired solution
Implement `neq` everywhere that `eq` exists (for values and signals).

### Additional contract requirements

- Add a public method `Logic.neq(dynamic other)` on the `Logic` class (in `lib/src/logic.dart`) that returns a `Logic` signal which is 1 when the operands differ, 0 when they are equal, and x when the comparison is indeterminate.
- Add a public method `LogicValue.neq(dynamic other)` on the `LogicValue` class (in `lib/src/values/logic_value.dart`) that returns a `LogicValue` which is zero when the operands are equal, one when they differ, and x when either operand is invalid. The `other` operand may be a `LogicValue` or an `int`.
