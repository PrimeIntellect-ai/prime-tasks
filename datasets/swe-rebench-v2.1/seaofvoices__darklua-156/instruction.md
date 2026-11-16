Remove interpolated strings
Add rule to remove interpolated strings. Simple strings can be converted to string expressions:

**Examples:**

```lua
return `...`
```

Converts into:

```lua
return "..."
```

More complex interpolated strings can be a chain of concatenation

```lua
return `...{true}`
```

Converts into:

```lua
return "..." .. tostring(true)
```

### Additional contract requirements

- With the default strategy, the input Lua source ``return `-{object}``` must transform exactly to `return string.format('-%s', tostring(object))`.
