Allow comparison of `data.Const` with `dict` and `list`
It would be nice, for tests, if this worked:

```python
>>> data.StructLayout({"a": 4}).const({"a": 0b0001}) == {"a": 0b0001}
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File ".../python3.12/site-packages/amaranth/lib/data.py", line 1076, in __eq__
    raise TypeError(
TypeError: Constant with layout StructLayout({'a': 4}) can only be compared to another view or constant with the same layout, not {'a': 1}
```

Currently you have to write assertions like this:

```
assert (await stream_get(ctx, stream)) == Const({"a", 0b0001}, stream.p.shape())
```
