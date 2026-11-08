Add delete by func
I really like otter, but what do miss (in comparison to ristretto for example) is something similar to a tag option. I need it sometimes to invalidate a part of the cache, and an easy option (in my opinion at least) to implement this would be to add a function to delete a part of the the cache depending on a function.

This would go along something like this:

```go
// DeleteByFunc removes the association for this key from the cache if the selectFunc returns true.
func (bs baseCache[K, V]) DeleteByFunc(selectFunc func(key K, value V) bool) {
	[HIDDEN]
}
```

You probably need a mutex, but the general idea should be clear.

Any additional ideas are appreciated.

### Additional contract requirements

- Add `(*Cache[K, V]) DeleteByFunc(f func(key K, value V) bool)`. It must remove every cache entry for which the predicate returns true and leave entries for which it returns false. The predicate receives each entry’s actual key and value.
