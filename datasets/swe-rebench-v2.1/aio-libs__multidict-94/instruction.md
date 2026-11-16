`pop()` is inconsistent
It now removes all keys but returns the last value
Should remove only first key.

`pop()` should be an alias for new method `.popone()` to mimic `get/getone`.

### Additional contract requirements

`MultiDict` provides a public method `popone(key[, default])` that removes and
returns the first value associated with `key`, preserving any later occurrences
of the same key. When `key` is absent, `popone` returns `default` if it is
provided, otherwise it raises `KeyError`. `pop` behaves as an alias for
`popone`.
