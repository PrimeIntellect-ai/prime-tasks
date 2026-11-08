Implement `ErrorOutOfGasSHA3` error state
Suppose to implement ErrorOutOfGasSHA3 to handle OOG error of SHA3 opcode. Could refer https://github.com/scroll-tech/zkevm-circuits/pull/419

### Additional contract requirements

- SHA3 requires 30 gas plus 6 gas for each 32-byte word in the input range, rounded up, and the incremental memory-expansion charge for that range. Memory expansion for `a` words costs `3a + floor(a² / 512)` gas; charge only the increase from the current memory size. A zero-length input incurs no memory-expansion charge, regardless of its offset.
- SHA3 is out of gas when the available gas is less than the total required gas; having exactly the required gas is sufficient.
