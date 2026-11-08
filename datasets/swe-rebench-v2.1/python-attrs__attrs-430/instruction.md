Exception when using auto_attribs and a attribute named property
Given a class like:

```python
@attr.s(auto_attribs=True)
class Foo:

    property: str
    other: str
```

Attrs is raising an exception:

```
Traceback (most recent call last):
  File "f.py", line 13, in <module>
    @attr.s(auto_attribs=True)
  File "/usr/local/lib/python3.6/site-packages/attr/_make.py", line 729, in wrap
    builder = _ClassBuilder(cls, these, slots, frozen, auto_attribs)
  File "/usr/local/lib/python3.6/site-packages/attr/_make.py", line 409, in __init__
    cls, these, auto_attribs
  File "/usr/local/lib/python3.6/site-packages/attr/_make.py", line 354, in _transform_attrs
    AttrsClass = _make_attr_tuple_class(cls.__name__, attr_names)
  File "/usr/local/lib/python3.6/site-packages/attr/_make.py", line 220, in _make_attr_tuple_class
    eval(compile("\n".join(attr_class_template), "", "exec"), globs)
  File "", line 1, in <module>
  File "", line 4, in BreaksAttributes
TypeError: 'property' object is not callable
```

What's odd here, is that it works fine as long as property is the *last* item in the class, e.g.:

```python
@attr.s(auto_attribs=True)
class Foo:

    other: str
    property: str
```

this works fine and doesn't raise an error.
