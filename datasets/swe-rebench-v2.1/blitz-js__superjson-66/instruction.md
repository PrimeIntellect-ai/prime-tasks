ReferenceError: Can't find variable: BigInt
Superjson is totally broken in Safari 13. Currently affecting my client's app :grimacing:

````
ReferenceError: Can't find variable: BigInt
```

I guess we need to first check if this (and any other new types like this) are available before trying to use them.

### Additional contract requirements

- When deserializing a BigInt value in a runtime where `BigInt` is unavailable, return its serialized string value (for example, `'1000'`).
