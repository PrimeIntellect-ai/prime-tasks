Regex support for more complex structures?
Currently, something like this is hard to capture:

```cpp
#define NB_VERSION_MAJOR 2
#define NB_VERSION_MINOR 0
#define NB_VERSION_PATCH 1
#define NB_VERSION_DEV   1 // A value > 0 indicates a development release
```

As we only have a `{value}` field.

### Additional contract requirements

The regex metadata plugin accepts an optional `remove` setting in addition to
`input`, `regex`, and `result`. `remove` is a regular expression; every match of
it in the formatted result is removed. When `remove` is omitted (or empty), the
formatted result is returned unchanged.
