Error message for source-expression containing invalid characters should be verbous.
Ex. https://cspvalidator.org/#headerValue[]=script-src+%D0%B0&strategy=intersection .
Say that chars outside ASCII 0x21-0x7E must be percent encoding or something like that

### Additional contract requirements

- For an invalid non-ASCII character encountered while parsing a directive value, the error message must have the exact form `expecting directive-value but found U+XXXX (c). Non-ASCII and non-printable characters must be percent-encoded`, where `XXXX` is the offending Unicode code point in uppercase hexadecimal, padded to at least four digits, and `c` is the offending character.
