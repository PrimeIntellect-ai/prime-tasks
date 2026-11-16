orderBy to accept array of strings instead
In the documents, it says:

`await Model.orderBy('-created_at', 'category_id')  `

is it possible to somehow pass an array of strings as the args?

### Additional contract requirements

- `orderBy` accepts either separate string arguments (for example `orderBy('-created_at', 'category_id')`) or a single array of strings (for example `orderBy(['-created_at', 'category_id'])`).
- Both forms produce the same `sort` parameter in the generated query.
- An empty array adds no sorting, the same as calling `orderBy()` with no arguments.
