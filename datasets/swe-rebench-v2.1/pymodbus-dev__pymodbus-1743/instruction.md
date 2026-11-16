Should `constants.Endian` be an enum?
### Versions

- Python: 3.11
- OS: Arch
- Pymodbus: 3.4.1

### Pymodbus Specific

- Server: tcp/rtu/ascii - all
- Client: tcp/rtu/ascii - all

### Description

I think it'd be more convenient if `Endian` was an actual enum, could help with type safety. For compatibility it could be made "str enum" and be fully compatible with literals.

All target python versions have support for enums.

If desired, I could work on this.

### Additional contract requirements

- `Endian` is a public enum in `pymodbus.constants` with the members `BIG` and `LITTLE`.
- Existing Endian string markers (`"@"`, `">"`, and `"<"`) remain accepted anywhere a byte-order or word-order value is accepted, with the same behavior as their corresponding enum values.
