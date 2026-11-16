Add Array Hashing
Add Array hashing, as described [here](https://docs.starknet.io/docs/Hashing/hash-functions/#array-hashing)

### Additional contract requirements

Expose the array-hashing behavior through `ArrayDigest(data ...*big.Int) (*big.Int, error)` in the `pkg/crypto/pedersen` package. It must hash arrays according to the linked StarkNet array-hashing specification.
