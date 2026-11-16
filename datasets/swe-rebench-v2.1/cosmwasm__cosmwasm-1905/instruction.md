Add MockApi::addr_make
Create a function that allows creating test addresses from arbitrary strings. As discussed in #1873.

E.g. in test code

```rust
let manager: Addr = api.addr_make("manager");
let user1: Addr = api.addr_make("Alice");
let user2: Addr = api.addr_make("Bob");
```

### Additional contract requirements

- Add a public method `MockApi::with_prefix(self, prefix: &'static str) -> Self` on `cosmwasm_std::testing::MockApi` that returns a `MockApi` configured to use `prefix` as the Bech32 human-readable part for generated addresses.
- The default Bech32 prefix used by `MockApi::default()` is `cosmwasm`.
- Add a public method `MockApi::addr_make(&self, input: &str) -> Addr` on `cosmwasm_std::testing::MockApi` that returns an `Addr`.
- The address returned by `addr_make` is a Bech32 string whose human-readable part is the configured prefix and whose data is the SHA-256 hash of the input string.
- Calling `addr_make` on a `MockApi` whose prefix is empty panics with a message that includes `Generating address failed with reason: invalid length`.
