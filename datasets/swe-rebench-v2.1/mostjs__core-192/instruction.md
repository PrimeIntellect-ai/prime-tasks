Return canonical empty in zip(), zipArray()
See #152

### Additional contract requirements

- `zip()` returns the canonical empty stream if either input is the canonical empty stream.
- `zipArray()` returns the canonical empty stream if any supplied stream is the canonical empty stream.
