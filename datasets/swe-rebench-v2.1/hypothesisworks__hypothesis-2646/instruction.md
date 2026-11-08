Iterable strategy gives elements of wrong types
It appears to give me tuples of ints when asked for iterables of instances of my own class. Generating individual instances of my own class the same way (via annotation) works perfectly.

Version: 5.37.4. Also tried current master - same issue.

Here's an example:

```python
from typing import Iterable

from hypothesis import given, infer


class My:
    def __init__(self, a: str):
        self.a = a


@given(i=infer)
def test_iterable(i: Iterable[My]):
    assert all(isinstance(e, My) for e in i)
```

Fails with:

```
    @given(i=infer)
>   def test_iterable(i: Iterable[My]):

repro.py:12:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

i = (0,)

    @given(i=infer)
    def test_iterable(i: Iterable[My]):
>       assert all(isinstance(e, My) for e in i)
E       assert False
E        +  where False = all(<generator object test_iterable.<locals>.<genexpr> at 0x7fcb12b74510>)

repro.py:13: AssertionError
--------------------------- Hypothesis ---------------------------
Falsifying example: test_iterable(
    i=(0,),
)
```
