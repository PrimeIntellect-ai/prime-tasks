Add power functionality
### Motivation

In SystemVerilog, power (`a**b`) is a useful function.

It would be nice to have a synthesizable `Module` and associated functions for generating hardware and SystemVerilog with powers.

### Desired solution

- Create a new `Module` that generates `a**b` in output SystemVerilog and appropriately simulates powers in the ROHD simulator.
- Add functions (probably to `Logic`) to automatically generate this module in a convenient API.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- Add a public method `LogicValue.pow(dynamic exponent)` on `LogicValue` that returns a `LogicValue`. The exponent may be an `int`, a `BigInt`, or a `LogicValue`. If either operand is invalid, the result is an `x`-filled value.
- Add a public method `Logic.pow(dynamic other)` on `Logic` that returns a `Logic` representing the base raised to the power of `other`, and that generates the power operation in output SystemVerilog.
