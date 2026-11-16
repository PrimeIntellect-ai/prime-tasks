add an "all" option for `typeCheckingMode`
since `strict` doesnt enable all rules
`typeCheckingMode = "off"` should mean: off
it needs to be updated to
```
reportInvalidTypeForm = false
reportMissingImports = false
```

and maybe others.

### Additional contract requirements

- `typeCheckingMode = "all"` must be accepted and must enable diagnostic rules that `strict` leaves disabled.
- The diagnostic rule set for a given mode is exposed through the public static method `ConfigOptions.getDiagnosticRuleSet(mode)`.
- In `off` mode, `reportInvalidTypeForm` and `reportMissingImports` are disabled.
