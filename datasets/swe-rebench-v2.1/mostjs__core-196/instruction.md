Return canonical empty in merge, mergeArray
See #152

### Additional contract requirements

- `merge(s, empty())` and `merge(empty(), s)` must emit exactly the events emitted by the non-empty stream `s`. The result need not be the same stream object as `s`.
- `mergeArray` must emit exactly the events of the non-empty streams it is given, ignoring canonical empty entries. The result need not be the same stream object as any input.
