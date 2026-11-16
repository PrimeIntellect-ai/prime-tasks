String interpolation doesn't compile
To be more precise, it seems like string interpolation does compile as long as:
- the "outer string" is empty (`"<--nothing here-->#{anything}<--nothing here-->"`);
- it's used only once (`"#{first_usage}"` is ok, `"#{first_usage}#{second_usage}"` is not).

Examples:
- Single interpolated string with nothing outside: `"#{"string"}"` compiles ✅
- Single interpolated variable with nothing outside:`"#{var}"` compiles ✅
- Single interpolated string with anything outside: `"Hello #{"World"}"` doesn't compile ❌
- Single interpolated variable with anything outside: `"Hello, #{name}!"` doesn't compile ❌
- Multiple interpolated string/variables with or without anything outside: `"#{var}#{"string"}"` doesn't compile ❌

Note that any of this examples gets parsed as intended, the error seems to arise during type checking.

### Additional contract requirements

String expressions with valid string-valued interpolations must type-check whether the string contains one interpolation surrounded by literal text or multiple interpolations, including consecutive interpolations with no literal segment between them.

Evaluating an interpolated string must preserve all literal text and interpolated string values in their source order.
