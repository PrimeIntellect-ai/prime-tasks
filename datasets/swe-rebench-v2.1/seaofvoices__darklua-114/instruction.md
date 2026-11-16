Normalize configuration to snake case
Darklua rules are currently written with snake case (like `remove_empty_do`) but most of its config is in kebab case (like the `retain-lines` generator). The upcoming configuration for bundling or require modes is also kebab case.

For consistency and simplicity, it would be easier if everything was using one kind of casing. Since darklua configuration file support json5, it is more useful if it uses snake case, because it does not need to wrap object properties in quotes:

```json5
{
    require_mode: { name: "path" }
}
```

Where as if we would use kebab case:
```json5
{
    "require-mode": { name: "path" }
}
```
