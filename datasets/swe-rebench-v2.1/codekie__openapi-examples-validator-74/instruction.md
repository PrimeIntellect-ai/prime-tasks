Catch YAML-errors and map them into serializable `ApplicationErrors`
See #67

Catch the error of the YAML-parser, [HIDDEN] and throw a serializable `ParseError`

### Additional contract requirements

- YAML parser failures encountered while parsing a specification must be exposed as serializable application errors of type `ParseError`.
- For invalid YAML that produces a parser error named `YAMLSemanticError` with message `Nested mappings are not allowed in compact mappings`, the `ParseError` message must be exactly `YAMLSemanticError: Nested mappings are not allowed in compact mappings`.
