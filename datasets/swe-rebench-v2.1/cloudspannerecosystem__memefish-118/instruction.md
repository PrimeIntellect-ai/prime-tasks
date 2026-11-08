Support JSON literals
Detected in #115.

References

* https://cloud.google.com/spanner/docs/reference/standard-sql/lexical#json_literals
* https://cloud.google.com/spanner/docs/working-with-json
* https://cloud.google.com/spanner/docs/reference/standard-sql/data-types#json_type

### Additional contract requirements

- The parser accepts JSON literals as expressions: the `JSON` keyword is followed by a SQL string literal.
- Represent parsed JSON literals with an `ast.JSONLiteral` node containing a `JSON` field for the JSON keyword position and a `Value` field holding the `*ast.StringLiteral` value.
