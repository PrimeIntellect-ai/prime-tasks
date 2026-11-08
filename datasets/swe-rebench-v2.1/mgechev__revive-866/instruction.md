support private `_UPPER_CASED_CONST` with `var-naming` and `upperCaseConst=true`
I see new feature added last week #851 with allowing to use uppercase constants.

I think there should be also a **private** uppercase constant support for this feature.

```
const _SOME_PRIVATE_CONST = "hello, world"
```

### Additional contract requirements

- With `var-naming` configured with `upperCaseConst` set to `true`, a constant whose name is all uppercase with a leading underscore (for example `_SOME_PRIVATE_CONST`, at top level or inside a `const (...)` block) must not be reported, in the same way that `SOME_CONST` is accepted.
- With `upperCaseConst` unset or set to `false`, all-uppercase constant names, including the underscore-prefixed form `_SOME_PRIVATE_CONST`, are still reported with the existing "don't use ALL_CAPS in Go names" diagnostic.
