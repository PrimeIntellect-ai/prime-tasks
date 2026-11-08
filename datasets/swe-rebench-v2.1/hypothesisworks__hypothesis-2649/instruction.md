Including optional fields in generated examples using the from_type strategy
Awesome, awesome project!

The `from_type` strategy is really useful when generating data from pydantic models (see https://github.com/samuelcolvin/pydantic/issues/1666), but it would be nice if it would recognise optional fields and _sometimes_ generate values for these fields, resulting in a more complete set of examples. The behaviour could be the same as that of the [fixed dictionaries strategy](https://hypothesis.readthedocs.io/en/latest/data.html?highlight=optional#hypothesis.strategies.fixed_dictionaries) when provided with the `optional` keyword argument, except that the optional fields are already known, from the model type hints.

To give a concrete example:

```python
from typing import Optional

from hypothesis import given
from hypothesis.strategies import from_type
from pydantic import BaseModel

class Adress(BaseModel):
    city: str
    street: str
    house_number: int
    postal_code: int


class Person(BaseModel):
    prename: str
    middlename: Optional[str]
    lastname: str
    address: Adress


@given(from_type(Person))
def test_me(person: Person):
    assert isinstance(person, Person)
```

It would be great if the behaviour was that the `middlename` field _may or may not_ be in the generated value. (Currently, it's always `None`.) Maybe something like:

```python
@given(from_type(Person, include_optional=True))
def test_me(person: Person):
    assert isinstance(person, Person)
```

Is this a sensible idea, or am I missing some other easy way to do this?

So far I've tried:

- Using `fixed_dictionaries` - not great as you either have to manually provide the required and optional fields and their strategies, or write your own functions to extract them from the pydantic model
- `@given(st.builds(Person, middlename=infer))` - `middlename` is always set, which isn't what we want.

### Additional contract requirements

- `hypothesis.strategies.builds(target, **kwargs)` accepts
  `hypothesis.infer` as a keyword value. When `infer` is passed for a parameter
  whose annotation is a concrete type and whose default value is `None`, the
  resulting strategy generates either `None` or a value of the annotated type.
- When `from_type` generates instances of a class with optional fields in its
  type hints, those fields should sometimes be `None` and sometimes have a value
  of their annotated type.
