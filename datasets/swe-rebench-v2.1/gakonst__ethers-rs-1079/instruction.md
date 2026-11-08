Invalid bindings are generated
**Version**
ethers v0.6.0 (https://github.com/gakonst/ethers-rs#fa042478)

**Platform**
Darwin MacBook-Pro.local 21.4.0 Darwin Kernel Version 21.4.0: Mon Feb 21 20:35:58 PST 2022; root:xnu-8020.101.4~2/RELEASE_ARM64_T6000 arm64

**Description**
When generating bindings with forge I noticed there seems to be an issue with serializing filters that have a u8 in them. You can recreate this issue by generating bindings for the LibDiamond contract that can be found here, https://github.com/mudgen/diamond-3/blob/master/contracts/libraries/LibDiamond.sol

I used the following command to generate the bindings:
`forge bind --bindings-path ./bindings --overwrite`

I am also on the latest version of foundry as well:
`forge 0.2.0 (d4c615b 2022-03-24T01:05:20.744764+00:00)`

However, I'm assuming this is an issue with ethers abigen not forge, hence why I created the issue here.

It generates the following code that causes the issue:

```rust
#[derive(
    Clone,
    Debug,
    Default,
    Eq,
    PartialEq,
    ethers :: contract :: EthEvent,
    ethers :: contract :: EthDisplay,
)]
#[ethevent(
    name = "DiamondCut",
    abi = "DiamondCut((address,uint8,bytes4[])[],address,bytes)"
)]
pub struct DiamondCutFilter {
    pub diamond_cut: Vec<(ethers::core::types::Address, u8, Vec<[u8; 4]>)>,
    pub init: ethers::core::types::Address,
    pub calldata: ethers::core::types::Bytes,
}
```

Attempting to compile the file it will throw the following error:

```
error[E0277]: the trait bound `u8: AbiArrayType` is not satisfied
   --> bindings/src/lib_diamond.rs:126:9
    |
126 |         pub diamond_cut: Vec<(ethers::core::types::Address, u8, Vec<[u8; 4]>)>,
    |         ^^^ the trait `AbiArrayType` is not implemented for `u8`
    |
    = note: required because of the requirements on the impl of `AbiArrayType` for `(H160, u8, Vec<[u8; 4]>)`
    = note: required because of the requirements on the impl of `AbiType` for `Vec<(H160, u8, Vec<[u8; 4]>)>`
```
