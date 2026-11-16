Remove crop from shape
[HIDDEN] Having now implemented some shaper scripts, recalled #1841, and consulted with @philrz, it seems like it would be better for `shape()` not to crop. This makes `shape()` less strict and more in-line with the overall schema flexibility of the system, as opposed to discarding any extra fields from the get-go. The fact that `shape()`  will likely be the default go-to shaping function for most users makes this change especially relevant. Of course, `crop()` remains available as a standalone function for situations that require it.

### Additional contract requirements

- `shape()` must preserve fields present in an input record but absent from the target schema, including extra fields nested within records.
