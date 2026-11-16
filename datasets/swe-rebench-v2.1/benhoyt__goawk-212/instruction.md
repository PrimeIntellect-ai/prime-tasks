Add support for new \u Unicode escape sequence
As per the addition to BWK's awk and Gawk. The `\u` must be followed by 1-8 hex digits. (Look up references/sources, perhaps in the BWK awk source code and/or the Gawk manual.)

### Additional contract requirements

- When `\u` is not followed by a hexadecimal digit, report `1-8 hex digits expected`; when its value is an invalid Unicode character, report `invalid Unicode character`.
