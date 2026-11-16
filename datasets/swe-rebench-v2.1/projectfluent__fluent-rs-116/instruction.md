Add FSI/PDI marks support
We should port the `withIsolation` part for the Resolver.

### Additional contract requirements

- By default, formatting must wrap each interpolated placeable value, including a variable value such as `$name`, in a Unicode FSI mark (`\u{2068}`) before the value and a PDI mark (`\u{2069}`) after it.
- `FluentBundle.set_use_isolating(false)` must disable those marks; setting it to `true` enables them.
