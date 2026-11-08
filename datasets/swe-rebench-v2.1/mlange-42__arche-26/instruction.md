Lock world during Query iteration
Arche does not (and will not) support adding or removing components od entire entities during query iteration. However, nothing prevents the user from trying it, with undefined behaviour.

As a first measure, lock the world when a query is created, and hand it back to unlock.

Later, add/remove operations could be buffered and executed at unlock.

### Additional contract requirements

- `World.Query(comps ...ID) Query` creates a query iterator over entities matching the given components and locks the world for the duration of the query.
- `Query.Next() bool` advances the iterator, returning `true` while matching entities remain and `false` once iteration is exhausted; reaching the end releases the world lock.
- `Query.Get(comp ID) unsafe.Pointer` returns a pointer to the requested component of the entity currently selected by the iterator.
- `Query.Close()` ends the iteration early and releases the world lock.
- `World.IsLocked() bool` reports whether any query currently holds the world lock.
- While the world is locked, `World.NewEntity`, `World.RemEntity`, `World.Add` and `World.Remove` panic.
- The world supports at most 64 concurrent active queries; creating another query while 64 are active panics.
- `newBitPool() bitPool` creates an initialized bit pool.
- `(*bitPool).Get() uint8` returns a fresh or recycled bit and panics once all 64 bits are allocated.
- `(*bitPool).Recycle(b uint8)` returns a previously obtained bit to the pool so it can be reused.
