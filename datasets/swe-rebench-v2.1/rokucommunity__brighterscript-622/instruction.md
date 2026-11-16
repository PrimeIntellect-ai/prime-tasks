Certain enums aren't being transpiled
Some code patterns seem to prevent enums from transpiling.

```
serviceField = m.entitlementService = someNamespace.authorization.EntitlementService.someEnumValue ? "enabled" : "disabled"
result = Direction.up = "up" or Direction.down = "down" and Direction.up = Direction.down
```

These issues can be mitigated by wrapping the enum expression in parens, but that's gross so we should fix this.
