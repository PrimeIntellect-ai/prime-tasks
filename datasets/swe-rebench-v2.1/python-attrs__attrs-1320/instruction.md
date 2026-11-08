`attr.filters.exclude` or `include` not simultaneously usable with `validators.in_` set.
When using one of the mentioned filter functions in `attrs.as_dict` or `as_tuple` on frozen nodes that have attributes with `attrs.validators.in_`  set as their validator, the following TypeError is thrown:

```pytb
  File "<>/venv/lib/python3.11/site-packages/attr/filters.py", line 63, in exclude_
    or attribute in attrs
       ^^^^^^^^^^^^^^^^^^
  File "<>/venv/lib/python3.11/site-packages/attr/_funcs.py", line 57, in asdict
    if filter is not None and not filter(a, v):
                                  ^^^^^^^^^^^^
  File "<>/venv/lib/python3.11/site-packages/attr/_next_gen.py", line 211, in asdict
    return _asdict(
           ^^^^^^^^
  [...]
TypeError: unhashable type: 'set'
```

Trying to execute line 63, in exclude_ (top of traceback) resulted in the following error:

```pytb
Traceback (most recent call last):
 [...]
  File "<attrs generated hash attr._make.Attribute>", line 2, in __hash__
    return hash((
           ^^^^^^
  File "<attrs generated hash attr.validators._InValidator>", line 2, in __hash__
    return hash((
           ^^^^^^
TypeError: unhashable type: 'set'
```

Therefore I suspect, that the issue lies in hashing of `attrs.validators.in_`.
