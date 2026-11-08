Generics support for `QueryResponses` derive macro
Currently the use of generics in query endpoint messages are not supported by the `#[derive(QueryResponses)]` macro.
By supporting generics in `QueryMsg` definitions developers can more easily modularise their smart-contracts.

Example:

```rust
#[cosmwasm_schema::cw_serde]
#[derive(QueryResponses)]
#[query_responses(nested)]
pub enum QueryMsg<BaseMsg, AppMsg = Empty> {
    /// A configuration message to a base implementation.
    Base(BaseMsg),
    /// Custom query
    App(AppMsg),
}
```

### Additional contract requirements

- `#[derive(QueryResponses)]` must support query message enums that declare generic type parameters, including parameters with explicit trait bounds and `where` clauses, and parameters with a default type.
- A query message enum annotated with `#[query_responses(nested)]` that declares generic type parameters must combine the subqueries of its generic child query enums into a single query schema.
