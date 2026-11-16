Make `bin` handle `_` for binary number separation
## Motivation
In SystemVerilog, you can make a binary number like `6'b11_00_11` to separate portions of the binary.  It would be nice to do that with ROHD.

## Desired solution
The `bin` function [HIDDEN]

## Alternatives considered
Current implementation requires only numbers 0 and 1.

### Additional contract requirements

- `bin` must ignore underscore characters in a binary string when determining its parsed numeric value.
