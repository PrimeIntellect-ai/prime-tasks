refactor GraphQL query shape to use `nodes` shorthand
### 📝 Provide a description of the new feature

Currently we are querying for the relay paginated shape (`edges` -> `node`).  We don't do anything currently with the edge information, so we can simplify our shape by going directly to `nodes`.

### ➕ Additional Information

_No response_
