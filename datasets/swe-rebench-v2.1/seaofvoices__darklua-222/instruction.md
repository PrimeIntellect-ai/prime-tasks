Preserve sign when evaluating zero
The `compute_expression` should not change the sign of `-0` to `0`, because it some cases it can change the sign of the result.

### Additional contract requirements

- Converting a negative-zero float into an expression (for example `Expression::from(-0.0)`) must produce a decimal number literal whose float value is negative zero (`-0.0`), preserving the sign instead of normalizing it to positive zero.


- For the `compute_expression` rule, `return -0`, `return -0 + -0`, and `return -0 - 0` must each generate exactly `return -0`.
