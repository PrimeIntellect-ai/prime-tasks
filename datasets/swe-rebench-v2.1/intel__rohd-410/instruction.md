Add reset signal to `FlipFlop`
## Motivation
It would be nice to use `FlipFlop` with a reset signal (optionally synchronous or asynchronous)

## Desired solution
Add optional named parameter(s) to `FlipFlop` that, when specified, add reset behavior.

## Alternatives considered
People can already achieve this using the `Sequential` block, but `FlipFlop` is convenient.

### Additional contract requirements

The `FlipFlop` constructor and the `flop` helper accept optional named `reset` and `resetValue` parameters. A supplied `reset` is a one-bit, active-high synchronous signal sampled on the rising edge of the clock. On an edge where reset is asserted, the output takes `resetValue` rather than the data input; if no reset value is supplied, the output takes zero. A reset value may be an integer, a `LogicValue`, or a same-width `Logic` signal. When reset is deasserted, normal flip-flop behavior continues, including any supplied enable. Asynchronous reset support is not required.
