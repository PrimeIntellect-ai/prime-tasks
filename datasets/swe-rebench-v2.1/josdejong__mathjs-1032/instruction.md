Additional arguments of OperatorNode's are silently ignored in derivative.
`OperatorNode`'s that only support two arguments (such as '-', '/' or '^') silently drop any additional arguments when calculating the derivative.

The `derivative` function should throw an error instead.

See also #1003

### Additional contract requirements

- `OperatorNode` has a public instance method `isUnary()` that returns `true` exactly when the node has exactly one argument, and `false` otherwise.
- `OperatorNode` has a public instance method `isBinary()` that returns `true` exactly when the node has exactly two arguments, and `false` otherwise.
- For unsupported operators and functions, the stringified error must include `Error: Operator "<op>" is not supported by derivative` and `Error: Function "<name>" is not supported by derivative`, respectively.
- For `/` operator nodes with additional arguments, the error must include `Error: Operator "/" is not supported by derivative, or a wrong number of arguments is passed`.
- For `^` operator nodes with additional arguments, the error must include `Error: Operator "^" is not supported by derivative, or a wrong number of arguments is passed`.
