`ReplicationOp` should support multi-bit replication
### Summary

PR https://github.com/intel/rohd/pull/203 introduced `ReplicationOp`, but only 1-bit `Logic`s are supported, it does support multi-bit `Logic`s.

### To Reproduce

Use `ReplicationOp` with a multi-bit value for the `bit` input.

### Expected behavior

It's probably nice to support multi-bit, but requires a bit more logic to handle that.

### Additional contract requirements

- Add a public method `Logic.replicate(int multiplier)` on `Logic` (declared in `lib/src/logic.dart`) that returns a new `Logic` whose width is `self.width * multiplier` and whose value is `self` repeated `multiplier` times. It throws an exception when `multiplier < 1`.
- Add a public method `LogicValue.replicate(int multiplier)` on `LogicValue` (declared in `lib/src/values/logic_value.dart`) that returns a new `LogicValue` consisting of the original value repeated `multiplier` times (width = original width × multiplier) for `multiplier >= 2`. It throws an exception when `multiplier < 1`.
- Constructing `ReplicationOp` with a multi-bit input must produce an output that repeats the entire input value for each requested copy.
