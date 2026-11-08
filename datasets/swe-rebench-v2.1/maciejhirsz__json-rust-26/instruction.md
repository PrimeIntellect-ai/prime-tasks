New codegen broken for some floats.
`assert_eq!(stringify(0.00001), "0.00001");` fails.

### Additional contract requirements

- Also, `stringify(0.000000000000001)` must produce exactly `0.000000000000001`.
