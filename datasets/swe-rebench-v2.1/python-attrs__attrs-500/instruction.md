Add a convenience flag for upcalling on Exception subclasses
Currently, these tests both fail on 2.7 and only the latter fails on 3.6.

```python
@attr.s
class E1(Exception):
    x = attr.ib()
    y = attr.ib()


def test_exception_init_called():
    e = E1(1, 2)
    assert e.args == (e.x, e.y) == (1, 2)


def test_exception_init_called_even_with_kw():
    e = E1(y=3, x=4)
    assert e.args == (e.x, e.y) == (4, 3)
```

If attrs is overriding `__init__` then this makes sense; `args` is filled in by `__init__` in 2.x and `__new__` in 3.x, but only pulling from the `*args` and never `**kwargs`. I discussed this a bit with @markrwilliams but I'm not sure what the best way to handle an attrs-ified exception would be. Maybe it's okay to consider `args` vestigal.

Mostly I'm raising this on the issue tracker because there are some references to using attrs for exceptions, but only indirectly. It'd be nice to have some documentation on a suggested approach either way.

### Additional contract requirements

- `attr.s` accepts an `auto_exc` keyword argument that defaults to `False`.
- `attr.make_class` accepts an `auto_exc` keyword argument that defaults to `False`.
- When `auto_exc=True` and the decorated class (or, for `attr.make_class`, the generated class) subclasses `Exception`, the resulting class behaves like a well-behaved exception class:
  - the values of the attributes that are `__init__` parameters are additionally available, in definition order, as a tuple in the instance's `args` attribute;
  - the instances are not comparable or hashable by value: equality falls back to identity and hashing raises `TypeError`;
  - `__str__` is left to the base exception implementation, so it renders the `args` tuple.
- All other existing parameters of `attr.s` and `attr.make_class` keep their original meanings.
