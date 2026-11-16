the trait `TokenizableItem` is not implemented for `ethers::prelude::Bytes`
**Version**
0.6.0

**Platform**
```
Darwin Mac-mini.local 21.2.0 Darwin Kernel Version 21.2.0: Sun Nov 28 20:29:10 PST 2021; root:xnu-8019.61.5~1/RELEASE_ARM64_T8101 arm64                                                                                                                            /0.0s
```
**Description**
Generated ABI for https://github.com/sushiswap/bentobox/blob/canary/deployments/mainnet/BentoBoxV1.json with `Abigen.generate`. However, it doesn't seem to compile because of a missing trait implementation. Fails at `BatchCall`

```rs
    #[doc = "Container type for all input parameters for the `batch`function with signature `batch(bytes[],bool)` and selector `[210, 66, 59, 81]`"]
    #[derive(
        Clone,
        Debug,
        Default,
        Eq,
        PartialEq,
        ethers :: contract :: EthCall,
        ethers :: contract :: EthDisplay,
    )]
    #[ethcall(name = "batch", abi = "batch(bytes[],bool)")]
    pub struct BatchCall {
        pub calls: ::std::vec::Vec<ethers::core::types::Bytes>,
        pub revert_on_fail: bool,
    }
```

Error:
```
error[E0277]: the trait bound `ethers::prelude::Bytes: TokenizableItem` is not satisfied
   --> src/contracts/IBentoBoxV1.rs:895:9
    |
895 |         ethers :: contract :: EthCall,
    |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ the trait `TokenizableItem` is not implemented for `ethers::prelude::Bytes`
    |
    = note: required because of the requirements on the impl of `Tokenizable` for `Vec<ethers::prelude::Bytes>`
    = note: required because of the requirements on the impl of `Tokenize` for `Vec<ethers::prelude::Bytes>`
    = help: see issue #48214
    = note: this error originates in the derive macro `ethers::contract::EthCall` (in Nightly builds, run with -Z macro-backtrace for more info)

error[E0277]: the trait bound `ethers::prelude::Bytes: TokenizableItem` is not satisfied
   --> src/contracts/IBentoBoxV1.rs:895:9
    |
895 |         ethers :: contract :: EthCall,
    |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ the trait `TokenizableItem` is not implemented for `ethers::prelude::Bytes`
    |
    = note: required because of the requirements on the impl of `Tokenizable` for `Vec<ethers::prelude::Bytes>`
    = note: required because of the requirements on the impl of `Tokenize` for `Vec<ethers::prelude::Bytes>`
    = note: 1 redundant requirement hidden
    = note: required because of the requirements on the impl of `Tokenizable` for `BatchCall`
note: required by a bound in `EthCall`
```

I am guessing abigen is missing code for handling bytes arrays -- `bytes[]`

### Additional contract requirements

- The `Bytes` type (exported as `ethers_core::types::Bytes`) must implement the ABI codec traits `AbiEncode` and `AbiDecode` (from `ethers_core::abi`), so that a `Bytes` value can be ABI-encoded with `AbiEncode::encode` and decoded back to an equal value with `AbiDecode::decode`.
