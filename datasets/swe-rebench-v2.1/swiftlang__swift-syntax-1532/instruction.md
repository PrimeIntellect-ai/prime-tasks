`SourceLocation` should not have an optional `line` and `column`
`SourceLocation` currently has optional `line` and `column` properties if it doesn’t have a `ComputedLocation`. We should [HIDDEN] make `line` and `column` non-optional.

### Additional contract requirements

- `SourceLocation.line` and `SourceLocation.column` must be non-optional integer properties.
