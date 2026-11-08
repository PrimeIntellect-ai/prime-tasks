VIP: native hex string literals
## Simple Summary
per title

## Motivation
make it easier to copy bytestrings which are in hex format

## Specification
introduce hex string literals like `x"abcd"`. the parser should treat `x"abcd"` the same as `b"\xab\xcd"`.

## Backwards Compatibility
backwards compatible

## Dependencies
none

## References

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/)

### Additional contract requirements

A native hex literal with an odd number of hexadecimal digits must be rejected, since it cannot represent a whole number of bytes.
