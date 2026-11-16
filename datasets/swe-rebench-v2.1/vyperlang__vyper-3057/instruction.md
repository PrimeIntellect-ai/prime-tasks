VIP: `epsilon(decimal)` builtin for decimal types
## Simple Summary
Add an `epsilon()` builtin which returns the smallest non-zero value for a decimal type.

## Motivation
Similar to https://github.com/vyperlang/vyper/issues/1923, it is nice to not have to type out these special constants (as is done for instance here: https://github.com/vyperlang/vyper/pull/2935/files#diff-86a0306fe1e101309bd0992f2780ec4f0c3dd319940131270904157845c9d9beR79)

## Specification
Add an `epsilon()` builtin which takes a `decimal` typedef as its argument, and returns the smallest non-zero value for that type. Currently as we only have one decimal type, this would be `epsilon(decimal) == 1e-10`. In general as we add more decimal types, `epsilon(Decimal[N, ...])` would return `1 / 10**N`. This is already in the typeinfo for decimals, it's just a matter of exposing as a builtin
https://github.com/vyperlang/vyper/blob/9a02a44d7b18ef3a618d2d1903283fd61aa71c88/vyper/codegen/types/types.py#L110-L112


## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/)

### Additional contract requirements

For the current `decimal` type, `epsilon(decimal)` must evaluate to exactly `1e-10`. Arguments that are not decimal type definitions must be rejected.
