Multiple alternatives validator
I'd like to validate that a field can be of several types, one of which is an iterator.

```py
from attrs.validator import instance_of

@define
class C:
  x: A | B | tuple[int, ...] = field(validator=instance_of((A, B, tuple)))
```

I can use `instance_of` to check the outer type `tuple`, but I can't use `deep_iterable` to validate that they are indeed the element type `int`.

Since we already have validators `and_` and `not_`, it may make sense to also add `or_`, so that I can represent this with

```py
from attrs.validator import instance_of, deep_iterable, or_

@define
class C:
  x: A | B | tuple[int, ...] = field(
    validator=or_(
      instance_of((A, B)),
      deep_iterable(instance_of(int))))
```

For comparison, this is how I'm writing a custom validator


```py
from attrs.validator import instance_of, deep_iterable

@define
class C:
  x: A | B | tuple[int, ...] = field()

  @x.validator
  def _validate_x(self, attr, value):
    v1 = instance_of((A, B))
    v2 = deep_iterable(instance_of(int))
    try:
      v1(self, attr, value)
    except TypeError:
      v2(self, attr, value)
```

### Additional contract requirements

- `or_` is exported in `attr.validators.__all__`.
- The returned validator's `repr` is `<or validator wrapping {validators!r}>`, where `{validators}` is the tuple of the wrapped validators after flattening.
- When no supplied validator is satisfied, the raised `ValueError` message is `None of {validators!r} satisfied for value {value!r}`.
- Nested `or_` results are flattened: `or_(or_(a, b), c)` wraps the validators `(a, b, c)`.
