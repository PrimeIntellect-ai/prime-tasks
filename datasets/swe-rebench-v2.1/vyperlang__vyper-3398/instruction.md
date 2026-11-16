VIP: Ternary operator
## Simple Summary

Add ternary operator to Vyper:

```vyper
@external
def hello(a: uint256, b: uint256) -> uint256:
    return a if a < b else b
```

### Additional contract requirements

- When compiling a ternary expression with a non-boolean condition or incompatible result-branch types, raise `InvalidType` or `TypeMismatch`.
