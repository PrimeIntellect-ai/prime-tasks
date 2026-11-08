Constants in generated SystemVerilog are unsized
## Describe the bug
Generated SystemVerilog from ROHD will be unsized like `0` or `15` instead of with an explicit size like `2'b0` and `16'd15`.  This can cause anything from a lint failure to a swizzling width mismatch/misalignment.

## To Reproduce
Generate SystemVerilog with constant value assignments using `Const`.

## Expected behavior
All constants are sized.

## Actual behavior
No constants are sized.
