Nested dictionaries in `py/state` incorrectly restored when tracking object references
Repro:
```python
import jsonpickle


class MyClass:
    def __init__(self, o):
        self.o = o

    def __getstate__(self):
        return self.__dict__


i1 = MyClass({"a": "a"})
i2 = MyClass({"b": "b"})
original = [i1, i1, i2, i2]

assert original[0] is original[1]  # ok
assert original[2] is original[3]  # ok

json = jsonpickle.encode(original)
# Correctly encoded as:
# [
#   {"py/object": "__main__.MyClass", "py/state": {"o": {"a": "a"}}},
#   {"py/id": 1},
#   {"py/object": "__main__.MyClass", "py/state": {"o": {"b": "b"}}},
#   {"py/id": 4}
# ]

decoded = jsonpickle.decode(json)
assert decoded[0] is decoded[1]  # ok
assert decoded[2] is decoded[3]  # fail
```

The assertion fails because `decoded[3]` is incorrectly set to the dictionary `{'a': 'a'}`, instead of the second instance of `MyClass`.

I think this only occurs for types that define `__getstate__` without also defining `__setstate__`.

[HIDDEN]
