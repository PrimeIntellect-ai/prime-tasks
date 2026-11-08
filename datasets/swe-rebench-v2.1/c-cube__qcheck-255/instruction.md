count cannot be zero
In `0.19` (since #220), the `~count` argument to `Test.make` can no longer be zero.

Why?

Is this documented?

Using a zero count can be used to disable a test. Real-life use:
https://github.com/andrenth/ocaml-stdint/blob/0.7.0/tests/stdint_test.ml#L6

### Additional contract requirements

- `Test.make` must accept `~count:0` and `~long_factor:0` (a zero value disables the test / long factor), and the stored value must be retrievable as `0` through the public accessors `QCheck2.Test.test_get_count` / `QCheck2.Test.test_get_long_factor` and `QCheck.Test.get_count` / `QCheck.Test.get_long_factor`.
- `Test.make` must reject a negative `~count` and a negative `~long_factor` by raising `Invalid_argument` during construction.
