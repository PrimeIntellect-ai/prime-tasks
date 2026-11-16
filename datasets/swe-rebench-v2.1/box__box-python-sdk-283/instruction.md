BaseObject.__eq__ is incorrect
`BaseObject.__eq__` only compares object ID, not type. So `client.file(id) == client.folder(id)` evaluates to `True`.

It should also return `NotImplemented` if the other object is not a `BaseObject`, but right now it will raise an exception (e.g. #151 ).

This is technically a backwards-incompatible change. We'll include this in the major version bump v2.0.0.

We also need to define `__hash__`.

I've started work on this already.
