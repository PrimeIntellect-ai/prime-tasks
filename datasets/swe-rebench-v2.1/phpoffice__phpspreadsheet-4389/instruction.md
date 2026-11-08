BIN2DEC, OCT2DEC, and HEX2DEC Return Strings Rather than Numbers
Excel returns numbers. Happened upon this working on PR #3341. Will fix it with a separate PR.

### Additional contract requirements

- For valid inputs, `ConvertBinary::toDecimal`, `ConvertHex::toDecimal`, and `ConvertOctal::toDecimal` return a number (`int` or `float`), never a numeric string. For invalid or unsupported inputs they return the `ExcelError` string constant (`ExcelError::NAN()` or `ExcelError::VALUE()`).
- `Calculation::calculateFormula` returns a numeric result (`int` or `float`) for valid formulas, or a string error code (one of the `ExcelError` constants, e.g. `ExcelError::NAN()`) for error results.
- In Gnumeric compatibility mode (`Functions::COMPATIBILITY_GNUMERIC`), a fractional numeric argument is accepted and converted using its integer part, so `=BIN2DEC(101.1)` evaluates to `5`, `=OCT2DEC(10.1)` evaluates to `8`, and `=HEX2DEC(10.1)` evaluates to `16`. In Excel and OpenOffice compatibility modes such a fractional argument is unsupported and yields `ExcelError::NAN()`.
