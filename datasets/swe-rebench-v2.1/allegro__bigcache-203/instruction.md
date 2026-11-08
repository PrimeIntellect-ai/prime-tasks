Implement new append function to use bigcache as index for internal database
Hi there,

I want to use bigcache for an index for my own "memory database".

My records have various fields and are indexed by a uint64 primary key. I now want to add secondary indices for columns pointing to primary keys. The data structure would look like the following:

bigcache[<columnvalue>] = `<uint64>,<uint64>,<uint64>`...

So for example my record has a column "city" and I want to an index on this column:

bigcache_city_index[newyork] = `<pk1>,<pk2>,<pk3>`...

From my point of view this cannot be done today because I will have a race condition between get() and set() calls.

Right now I am thinking about the following:

- Implement new "AppendUint64(key, id)"
[HIDDEN]

What are your thoughts about this?

Thank you,
Stefan

### Additional contract requirements

- The required public method is `Append(key string, entry []byte) error` on `*BigCache`; the `AppendUint64(key, id)` sketch above is superseded by this signature.
- `Append` returns `nil` on success.
- `Append` adds the provided entry bytes after the value stored under the key. If the key is absent, it creates the key with the provided bytes as its value.
- Concurrent appends to the same key must not lose data: each successful append's entry bytes must be included exactly once in the resulting value.
