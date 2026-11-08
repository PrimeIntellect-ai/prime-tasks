[HIDDEN]

For Pydantic models, Hypothesis inspects the `__signature__` [2] and will also use the equivalent of a `just(default_value)` strategy for fields with a `default_value` (cf. example below). It would be nice if we could also choose to use an [HIDDEN] in this scenario. What would be the recommended workaround for that?

Side question: why was the default strategy for kwargs/fields with default values chosen to be `just(default_value)` instead of `just(default_value) | from_type(type_annotation)`?

```python
from typing import Optional
import hypothesis.strategies as st
from pydantic import BaseModel

class Foo(BaseModel):
    bar: int
    baz: Optional[str] = None

st.from_type(Foo).example()  # `baz` will always be `None`, even though you might expect to see some `str`s
```

[1] https://hypothesis.readthedocs.io/en/latest/details.html#inferred-strategies
[2] https://github.com/HypothesisWorks/hypothesis/pull/2388

### Additional contract requirements

- When `st.from_type()` generates instances by inspecting a callable signature, a positional-or-keyword or keyword-only parameter with both a default and a type annotation must be able to take either its default value or a value matching its annotation.
