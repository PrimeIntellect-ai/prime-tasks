Fix for when obj is `UnionType` in `_utils._apply_params`
### Description

Hi. I'm using Python 3.13 and installing the package directly from this git repo.

I had an issue with `_utils._apply_params` - I don't have a minimal example, but here's the traceback:

```
...
  File ".../mycode.py", line 264, in decode
    return msgspec.msgpack.decode(item, **kwargs)
    ^^^^^^^^^^^^^^^
  File ".../.venv/lib/python3.13/site-packages/msgspec/_utils.py", line 111, in get_class_annotations
    mro, typevar_mappings = _get_class_mro_and_typevar_mappings(obj)
      ^^^^^^^^^^^^^^^^^
  File ".../.venv/lib/python3.13/site-packages/msgspec/_utils.py", line 88, in _get_class_mro_and_typevar_mappings
    inner(obj, {})
      ~~~^^^^^^^^^
  File ".../.venv/lib/python3.13/site-packages/msgspec/_utils.py", line 86, in inner
    inner(b, new_scope)
    ^^^^^^^
  File ".../.venv/lib/python3.13/site-packages/msgspec/_utils.py", line 79, in inner
    args = tuple(_apply_params(a, scope) for a in c.__args__)
    ^^^^^^^^^^^
  File ".../.venv/lib/python3.13/site-packages/msgspec/_utils.py", line 79, in <genexpr>
    args = tuple(_apply_params(a, scope) for a in c.__args__)
    ^^^^^^^^^^^
  File ".../.venv/lib/python3.13/site-packages/msgspec/_utils.py", line 55, in _apply_params
    args = tuple(mapping.get(p, p) for p in params)
    ^^^^^^^^^^^^^^^
TypeError: 'getset_descriptor' object is not iterable
```

I found that this was due to `_utils._apply_params` being called with `obj == types.UnionType`. UnionType returns a descriptor for `__parameters__`.

```pycon
>>> type(int | str).__parameters__
<attribute '__parameters__' of 'types.UnionType' objects>
```

I've pasted my workaround below:

```py
[HIDDEN]
```

### Additional contract requirements

- `get_class_annotations` must not raise when a generic class is parameterized with `types.UnionType` (the class itself, whose `__parameters__` is a non-iterable descriptor); the corresponding field resolves to `types.UnionType`.
