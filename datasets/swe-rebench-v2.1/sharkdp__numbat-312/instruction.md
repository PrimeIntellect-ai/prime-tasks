Extended number formatting
It would be great to extend the way we can print numbers using string interpolations. We could start simple and add support for precision-control:
```
print("{pi:.3}")
```

We should stay compatible with what Python/Rust do for numbers.

### Additional contract requirements

- For decimal number formatting, a precision `.N` specifies the number of digits after the decimal point; values are rounded as needed and padded with trailing zeros to that precision. A leading `+` requests an explicit sign for nonnegative values, and a leading `0` may be used with a precision.
- The Python/Rust compatibility request covers only the formatting conventions explicitly described here; it does not require support for other formatting flags, width or alignment rules, or numeric type codes.
- Format specifiers that cannot be applied to a value must be rejected with an error instead of crashing. The exact error messages are:
  - An unknown format code for a numeric value produces `Incorrect type for format specifiers: Unknown format code '<code>' for type` (for example, `"{200:x}"` produces `Incorrect type for format specifiers: Unknown format code 'x' for type`).
  - A format specifier with a missing precision produces `Invalid format specifiers: Format specifier missing precision` (for example, `"{200:.}"`).
