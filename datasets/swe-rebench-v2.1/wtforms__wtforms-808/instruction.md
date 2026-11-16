Flags repr is useless
The repr of the Flags class shows only the keys, but in wtforms3 flags can have a value, so the mere presence is no longer useful. Instead it should show the value OR omit flags that are false.

### Additional contract requirements

- For a Flags instance whose required flag is True, `repr(flags)` must be exactly `<wtforms.fields.Flags: {required=True}>`.
