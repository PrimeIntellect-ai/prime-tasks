FR: json.valid
As Starlark doesn't include `try` and `except`, it would be valuable to have a `json.valid` or similar function to enable custom handling (overwrite, `fail`, etc) of invalid json encoding.

### Additional contract requirements

Callers must be able to handle invalid JSON without being limited to an evaluation error. A public JSON API may let callers detect validity and choose their own response, or let callers provide a value to return when decoding fails. In the decode-fallback form, callers can pass that value as `json.decode(s, default=value)`, including `None`. Valid JSON must continue to decode to its corresponding Starlark value.
