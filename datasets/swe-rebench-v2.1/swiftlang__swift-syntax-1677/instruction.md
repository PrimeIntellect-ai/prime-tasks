Wrong diagnostics for ternary expression when only the colon is missing
### Description

When diagnostics are generated for ternary expressions where the `:` is missing but both of the first and second choice expressions are present, the incorrect diagnostic message is used and the wrong Fix-It is applied.


### Steps to Reproduce

Example:
```swift
foo ? 1 2
```

This results in the following diagnostic message and Fix-It:
```
expected ':' and expression after '? ...' in ternary expression
```
```swift
foo ? 1 : <#expression#>2
```


As the expression isn't missing in the example I expected the following diagnostic message and Fix-It:
```
expected ':' after '? ...' in ternary expression
```
```swift
foo ? 1 : 2
```

### Additional contract requirements

- When the second choice expression is absent, as in `foo ? 1` at end of input or `condition ? 1` followed on the next line by `someOtherVariable`, emit the diagnostic `expected ':' and expression after '? ...' in ternary expression` with the fix-it `insert ':' and expression`. Applying the fix-it must produce, respectively, `foo ? 1 : <#expression#>` and `condition ? 1 : <#expression#>\nsomeOtherVariable`.
