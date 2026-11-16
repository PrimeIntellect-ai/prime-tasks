Forwarding serde attributes
In messages, serde attributes should be forwarded for its fields.

Let's consider a function:

```rust
fn foo(&self, _: (DepsMut, Env, MessageInfo), #[serde(default)] field: bool) -> Result<Response, ContractError> {
  todo!()
}
```

Obviously, I want my `field` to have the `#[serde(default)]` attribute so it is optional and `false` by default. Basically, all `serde` attributes should be moved to a new place.

### Additional contract requirements

- The forwarded serde attributes apply to the generated message fields, so a field annotated `#[serde(default)]` on a method parameter may be omitted when deserializing the generated message and then takes its type's default value.
