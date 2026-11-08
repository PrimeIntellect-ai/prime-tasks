`kw_only` with `default` breaks `__attrs_pre_init__` call
The following code raises SyntaxError
```python
from attrs import define, field

@define
class A:
    a: int = field(kw_only=True, default=3)

    def __attrs_pre_init__(self, _):
        pass
```
```python
Traceback (most recent call last):
  File "/home/user/attrs_pre_init.py", line 4, in <module>
    @define
     ^^^^^^
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_next_gen.py", line 153, in define
    return wrap(maybe_cls)
           ^^^^^^^^^^^^^^^
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_next_gen.py", line 144, in wrap
    return do_it(cls, True)
           ^^^^^^^^^^^^^^^^
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_next_gen.py", line 90, in do_it
    return attrs(
           ^^^^^^
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_make.py", line 1715, in attrs
    return wrap(maybe_cls)
           ^^^^^^^^^^^^^^^
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_make.py", line 1694, in wrap
    builder.add_init()
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_make.py", line 1090, in add_init
    _make_init(
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_make.py", line 2181, in _make_init
    init = _make_method(
           ^^^^^^^^^^^^^
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_make.py", line 345, in _make_method
    _compile_and_eval(script, globs, locs, filename)
  File "/home/user/.venv/lib/python3.12/site-packages/attr/_make.py", line 317, in _compile_and_eval
    bytecode = compile(script, filename, "exec")
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "<attrs generated init __main__.A>", line 2
    self.__attrs_pre_init__(a=attr_dict['a'].default=a=attr_dict['a'].default)
                                                    ^
SyntaxError: invalid syntax
```

### Additional contract requirements

- When `__attrs_pre_init__` accepts a keyword-only parameter matching a `kw_only` field, it must receive that field’s value under the matching keyword name. If the field is omitted during construction, the hook must receive its default value.
