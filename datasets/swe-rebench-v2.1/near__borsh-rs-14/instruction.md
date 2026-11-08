bug: could not find `result` in `core`
After updating to `near-sdk` = `3.0.0-pre-release` which uses borsh `0.8.1` the contract build generates the following error:
```
error[E0433]: failed to resolve: could not find `result` in `core`
   --> src/lib.rs:146:10
    |
146 | #[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
    |          ^^^^^^^^^^^^^^^^
    |          |
    |          could not find `result` in `core`
    |          in this macro invocation
    |
   ::: /Users/ekwork/.cargo/registry/src/github.com-1ecc6299db9ec823/borsh-derive-0.8.1/src/lib.rs:34:1
    |
34  | pub fn borsh_deserialize(input: TokenStream) -> TokenStream {
    | ----------------------------------------------------------- in this expansion of `#[derive(BorshDeserialize)]`

error[E0433]: failed to resolve: could not find `result` in `core`
   --> src/lib.rs:146:28
    |
146 | #[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
    |                            ^^^^^^^^^^^^^^
    |                            |
    |                            could not find `result` in `core`
    |                            in this macro invocation
    |
   ::: /Users/ekwork/.cargo/registry/src/github.com-1ecc6299db9ec823/borsh-derive-0.8.1/src/lib.rs:11:1
    |
11  | pub fn borsh_serialize(input: TokenStream) -> TokenStream {
    | --------------------------------------------------------- in this expansion of `#[derive(BorshSerialize)]`

error: aborting due to 2 previous errors
```

Repro:
```bash
git clone https://github.com/evgenykuzyakov/oysterpack-near-stake-token
cd oysterpack-near-stake-token
git checkout borsh-bug
cd contract
./build.sh
```

### Additional contract requirements

Borsh serialization and deserialization derives must compile in a consumer crate that declares a local module named `core`.
