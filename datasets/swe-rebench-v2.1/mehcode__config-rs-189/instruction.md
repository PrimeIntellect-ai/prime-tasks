Function misnamed, should corrrelate to type
Rust has types for both `str` and `String`. There are tons of functions in *std* and other crates related to the two, `as_str()`, `as_string()`, `from_string()`, `to_string()`, `to_str()`, etc.

This function is cross wired:

https://github.com/mehcode/config-rs/blob/2c0b201055be60ec45e258adcc6c4b6e01bcd627/src/config.rs#L172

It should either be named `get_string()` or return a `str` but not switch them out! Perhaps there should be two functions, one for each...

### Additional contract requirements

The string getter on `Config` must be renamed from `get_str` to `get_string`, and it must return `String` (not `&str`). The corresponding method on `Value` is `into_string(self) -> Result<String>`, which consumes the value and returns its inner `String`.
