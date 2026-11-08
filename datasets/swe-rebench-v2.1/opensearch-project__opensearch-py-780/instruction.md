[BUG] `TypeError` error when using a `.filter(...)` on a `Search` object.
### What is the bug?
Get a `TypeError` error when using a `.filter("terms", ...)` on a `Search` object.

### How can one reproduce the bug?
Having a str instead of an int for `Bool.filter` or `Bool.must` attributes when reach the `Bool.__and__` method.
This case can happen when using string based percent (eg: `"50%"`) instead of pure integer (eg: `50`) for `minimum_should_match`.

### What is the expected behavior?
Accept `50`, `"50"` or `"50%"` as valid values.

### Do you have any additional context?
A [TODO statement](https://github.com/opensearch-project/opensearch-py/blob/main/opensearchpy/helpers/query.py#L222) is present in the code for this specific case.
This TODO statement date back at least from the [opensearch-dsl 1.0](https://github.com/opensearch-project/opensearch-dsl-py/blob/1.0/opensearch_dsl/query.py#L224).

### Additional contract requirements

- Combining two Bool queries that use the supported `minimum_should_match` values must retain clauses from both queries.
- Applying `.filter("terms", ...)` to a Search with an existing string `minimum_should_match` must complete and include the requested filter.
