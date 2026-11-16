AttributeError: name with frozendict[..., ...] and subclass (maybe Mapping+GenericAlias issue?)
# Bug

Using a [`frozendict`](https://github.com/Marco-Sulla/python-frozendict) as a model field works normally/correctly but when subscripted (eg: `frozendict[str, int]`), pydantic errors in some weird ways:
- the output has a `dict` (similar to #2311 and others, except even converting to `frozendict` explicitly or in a `@validator` doesn't work)
- on model subclasses, the `field.outer_type_` seems to be botched and missing attributes (but works fine on the original defining class)

```py
# pip3 install frozendict
from frozendict import frozendict
from pydantic import BaseModel


class Base(BaseModel):
    a: frozendict
    b: frozendict[str, int]


class Sub(Base):
    pass


def inspect(m: BaseModel):
    print(f"\t{m.__name__}\n")
    print(m(a=frozendict(a=1), b=frozendict(b=1)))
    print(m.__fields__)
    print(m.__fields__["b"].outer_type_)


# This doesn't error, but the sub-typed variant is replaced with a dict and the Field is a Mapping
inspect(Base)
# This errors when inspecting `b` ModelField.outer_type_, seemingly trying to access an uninitialized .name
inspect(Sub)
```
outputs
```
        Base

a=frozendict({'a': 1}) b={'b': 1}
{'a': ModelField(name='a', type=frozendict, required=True), 'b': ModelField(name='b', type=Mapping[str, int], required=True)}
frozendict.core.frozendict[str, int]
        Sub

a=frozendict({'a': 1}) b={'b': 1}
{'a': ModelField(name='a', type=frozendict, required=True), 'b': ModelField(name='b', type=Mapping[str, int], required=True)}
Traceback (most recent call last):
  File "/tmp/pydantic_error.py", line 25, in <module>
    inspect(Sub)
  File "/tmp/pydantic_error.py", line 19, in inspect
    print(m.__fields__["b"].outer_type_)
  File "pydantic/utils.py", line 396, in pydantic.utils.Representation.__repr__
  File "pydantic/utils.py", line 375, in genexpr
  File "pydantic/utils.py", line 375, in genexpr
  File "pydantic/fields.py", line 951, in pydantic.fields.ModelField.__repr_args__
AttributeError: name
```

The `type(frozendict[str, int])` is a `GenericAlias` and otherwise seems to be normal:

```
>>> type(frozendict[str, str])
<class 'types.GenericAlias'>
>>> get_origin(frozendict[str, str])
<class 'frozendict.core.frozendict'>
>>> get_args(frozendict[str, str])
(<class 'str'>, <class 'str'>)
>>>
>>>
>>> type(dict[str, str])
<class 'types.GenericAlias'>
>>> get_origin(dict[str, str])
<class 'dict'>
>>> get_args(dict[str, str])
(<class 'str'>, <class 'str'>)
```

### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.8.2
            pydantic compiled: True
                 install path: /Users/jacobhayes/src/github.com/replicahq/artigraph/.wt/type-dispatch/.direnv/python-3.9.6/lib/python3.9/site-packages/pydantic
               python version: 3.9.6 (default, Jul 20 2021, 13:51:27)  [Clang 12.0.5 (clang-1205.0.22.9)]
                     platform: macOS-11.4-x86_64-i386-64bit
     optional deps. installed: ['typing-extensions']
```

### Additional contract requirements

- A field annotated with a subscripted subclass of `dict` (for example `frozendict[str, int]` from the `frozendict` package, or a user-defined `dict` subclass) must validate to an instance of that same class rather than a plain `dict`. Keys and values must still be validated against the subscripted types.
- A subscripted dict-subclass field inherited by a subclass of a model must behave the same as on the model that defines it: inspecting its `outer_type_` and printing the subclass's `__fields__` must work.
