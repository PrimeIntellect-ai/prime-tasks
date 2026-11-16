Add fault tolerant parsing for `case` expressions
Currently, `case something` is a syntax error (obviously). The problem is, the language server cannot provide autocomplete when typing the subject of the case expression. We could make this fault tolerant in the same way as `record.`, to allow for a better LSP experience.

### Additional contract requirements

- A `case` expression that is missing its body must be parsed without a syntax
  error, so that analysis can continue.
- When type checking such a `case` expression, the compiler must report an error
  whose title is `Missing case body`, whose message is
  `This case expression is missing its body.`, and which points at the whole
  `case` expression.
