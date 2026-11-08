Mocks: support large bytes (> 31 bytes) when using setVariable
**Is your feature request related to a problem? Please describe.**
Currently, an error is thrown when using `setVariable` in a variable of type `bytes` and sending an string larger than 31 bytes

**Describe the solution you'd like**
Bytes larger than 31 bytes do have an special handling in the storage, we need to adapt.

**Additional context**
From [Hardhat Docs](https://docs.soliditylang.org/en/v0.6.8/internals/layout_in_storage.html):
> [HIDDEN] This means that you can distinguish a short array from a long array by checking if the lowest bit is set: short (not set) and long (set).

There is an skipped test that should be unskipped as soon as this is working:
`Mock: Editable storage logic - should be able to set bytes`

### Additional contract requirements

- `setVariable` must support assigning `bytes` values longer than 31 bytes, and the mocked contract must observe the value that was assigned.
