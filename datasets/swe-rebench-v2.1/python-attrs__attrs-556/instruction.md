Attrs deletes any non-None class attributes
Currently, `attrs` will delete any non-`None` class attributes when `_ClassBuilder._delete_attribs` is `True` (i.e. when attributes are specified via class attributes, not directly via `these` field).
According to comment on [_make.py:502](https://github.com/python-attrs/attrs/blob/master/src/attr/_make.py#L502), this is intended to remove `attr.ib` instances from the class.
But it does not play well with attributes declared using PEP 484 type annotations and `auto_attribs=True` argument to `attr.s`, because any attribute with non-`None` default value specified will be pruned from the class, while attributes with `None` value are retained.
This leads to unexpected behaviour in many cases, in particular when generating documentation using `Sphinx` `autosummary` extension which relies on class introspection.
I think we should remove only `attr.ib` instances, not any not-None fields. At least in `auto_attribs` mode. Or at least fix the comment.

Attrs version checked: 19.1.0
Code to reproduce:
```
import attr
import typing

@attr.s(auto_attribs=True)
class Foo:
    bar: int = 42
    baz: typing.Any = None

print([f for f in dir(Foo) if not f.startswith('_')])  # ['baz']
print(Foo.baz)  # 42
print(Foo.bar)  # AttributeError
```

### Additional contract requirements

When attributes are collected from class attributes (i.e. when `_ClassBuilder._delete_attribs` is `True`, as with `@attr.s(auto_attribs=True)`), the class attributes for *all* collected attributes are removed from the class, including those whose default value is `None`. `None` must not be treated as a sentinel meaning "no class attribute": an attribute such as `baz: typing.Any = None` must be removed from the class just like `bar: int = 42`, so that accessing `Foo.baz` on the class raises `AttributeError` (for non-slotted classes).
