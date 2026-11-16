TypeError thrown from valid Union type
We've been using dataclasses-jsonschema for awhile.  After updating from 2.15.1 to 2.15.2. the following errors started to occur:

```
  File "/Users/XXX/.virtualenvs/customer-implementations/lib/python3.7/site-packages/dataclasses_jsonschema/__init__.py", line 420, in to_dict
    value = self._encode_field(f.field.type, value, omit_none)
  File "/Users/XXX/.virtualenvs/customer-implementations/lib/python3.7/site-packages/dataclasses_jsonschema/__init__.py", line 360, in _encode_field
    return encoder(field_type, value, omit_none)
  File "/Users/XXX/.virtualenvs/customer-implementations/lib/python3.7/site-packages/dataclasses_jsonschema/__init__.py", line 304, in encoder
    def encoder(ft, val, o): return cls._encode_field(unwrap_optional(ft), val, o)
  File "/Users/XXX/.virtualenvs/customer-implementations/lib/python3.7/site-packages/dataclasses_jsonschema/__init__.py", line 323, in _encode_field
    for variant in field_args:
  File "/Users/XXX/.virtualenvs/customer-implementations/lib/python3.7/site-packages/dataclasses_jsonschema/__init__.py", line 322, in <lambda>
    field_args = filter(lambda x: not issubclass(x, primitives), field_type.__args__)
TypeError: issubclass() arg 1 must be a class
```

reverting back to 2.15.1 resolved the error.

Confirmed that the order of variables on line 322 is wrong.
