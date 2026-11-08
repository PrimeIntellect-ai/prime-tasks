Dictionary identity not preserved through roundtrip
On jsonpickle 1.1:

```
>>> import jsonpickle
>>> x = {}; y = jsonpickle.decode(jsonpickle.encode([x, x]))
>>> y[0]['hi'] = 3
>>> y[1]
{}
```

I didn't see any warnings about this in the doc and `list`s seem to survive fine.  Adding a custom handler to try to trigger the id serialization didn't work.

Actually, trying with some more mutable builtin types - `set` identity doesn't appear to be preserved either.

This is an important use case for us since we need to serialize user data and can't reasonably request them to prevent duplicate dictionaries in their graphs.
