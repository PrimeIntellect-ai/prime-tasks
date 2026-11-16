Handling boolean form values
Currently, we consider valid booleans to be only  the strings `"true"` and `"false"`, unlike `strconv.ParseBool()` which correctly converts `"1", "t", "T", "true", "TRUE", "True", "0", "f", "F", "false", "FALSE", "False"` into `bool`. We should discuss the implications of this and decide whether we want to use `strconv.ParseBool()` in the `safehttp.Form` implementation.

### Additional contract requirements

The decision above is resolved as follows: `safehttp.Form` must use `strconv.ParseBool()` semantics when parsing boolean form values.

- `Form.Bool(param, defaultValue)` must accept exactly the strings that `strconv.ParseBool()` accepts: `"1", "t", "T", "true", "TRUE", "True"` convert to `true`, and `"0", "f", "F", "false", "FALSE", "False"` convert to `false`.
- For any other value, `Form.Bool` must return the provided default value and record a non-nil error retrievable via `Form.Err()`.
