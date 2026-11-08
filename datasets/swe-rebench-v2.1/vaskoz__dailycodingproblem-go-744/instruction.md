Day 368
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Implement a key value store, where keys and values are integers, with the following methods:

* `update(key, vl)`: updates the value at `key` to `val`, or sets it if doesn't exist
* `get(key)`: returns the value with key, or `None` if no such value exists
* `max_key(val)`: returns the largest key with value `val`, or `None` if no key with that value exists

For example, if we ran the following calls:
```
kv.update(1, 1)
kv.update(2, 1)
```
And then called `kv.max_key(1)`, it should return `2`, since it's the largest key with value `1`.

### Additional contract requirements

In the Go package for this problem, provide a `NewKeyValueStore` constructor returning a store with `Update(key, val int)`, `Get(key int) (int, error)`, and `MaxKey(val int) (int, error)` methods. The lookup methods must return a non-nil error when the requested key or value has no association.
