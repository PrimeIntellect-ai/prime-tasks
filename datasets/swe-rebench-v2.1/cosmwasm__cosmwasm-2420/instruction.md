Replace `serde-json-wasm` with `serde_json`
`serde-json-wasm` was originally created to remove floating point instructions from smart contracts to allow for JSON de-/serialization inside of contracts.

Since we fixed that with v1.5, there is no real need for `serde-json-wasm` anymore. It pretty much only adds a maintenance burden. Therefore we agreed to replace `serde-json-wasm` inside the CosmWasm project with `serde_json`.

### Additional contract requirements

The public JSON serialization API of `cosmwasm_std` (package `std`) is:

- `from_json<T>(value: impl AsRef<[u8]>) -> StdResult<T>` in `packages/std/src/serde.rs`: deserializes UTF-8 JSON bytes into `T`, returning `Err(StdError::parse_err)` when the JSON is invalid or cannot be deserialized.
- `to_json_string<T>(data: &T) -> StdResult<String>` in `packages/std/src/serde.rs`: returns the JSON string, or `Err(StdError::serialize_err)` on serialization failure.

JSON serialization and deserialization must support floating-point numbers (`f32` and `f64`).
