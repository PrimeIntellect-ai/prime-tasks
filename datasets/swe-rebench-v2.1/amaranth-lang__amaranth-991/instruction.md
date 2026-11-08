`Signature.create`'s `path` argument should probably default to `tracer.get_var_name()`
This change doesn't require an RFC.

It is tagged for the 0.4 milestone because this would change the signature from:

```python
def create(self, *, path=()):
```

to

```python
def create(self, *, path=None, src_loc_at=0):
```

and affects downstream and example code (which was how this bug was discovered).

The `SignatureMembers.create` method (which actually creates the signals) should have the same modifications done to it, and forward `src_loc_at` to the created signals. Right now, the source locations for all `lib.wiring`-created signals will point within `lib.wiring`, which makes them useless. Ideally the source location of the `In(...)`/`Out(...)` expression would be also preserved, but we aren't set up to do that in a nice way at the moment.

While we're at it: `FlippedSignature.create` should probably forward all unrecognized args/kwargs, too.
