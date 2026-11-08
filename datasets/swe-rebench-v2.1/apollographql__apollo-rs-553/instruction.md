Operations with empty queries should not parse
## Description
According to the GraphQL grammar spec variable definitions should always contain at least one variable meaning that `query Op() { field }` should be invalid.

See [spec](https://github.com/graphql/graphql-spec/blob/afc0a35d271ba9502c3c68aeda6e6c6fbc223774/spec/Appendix%20B%20--%20Grammar%20Summary.md?plain=1#L212).

### Steps to reproduce
Parse this example query https://github.com/apollographql/apollo-rs/compare/main...allancalix:apollo-rs:invalid-query

### Expected result
The query does not return a valid parse tree and should return errors.

### Actual result
The query is treated as having an empty set of variables.

### Environment
- `apollo-rs` crate: apollo-parser
- Crate version: `HEAD`

### Additional contract requirements

- When an operation's variable definitions are empty (for example `query Op() { field }`), the parser must report an error whose message is `expected a Variable Definition`.
