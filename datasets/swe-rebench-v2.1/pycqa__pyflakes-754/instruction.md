Error when referencing a class yet not declared inside function
I am facing a bug.

I created this example to test all behaviours I can foresee and spotted a bug:

```python
from typing import Optional

class InnerModel1:
        model2: "Model2"
        mode2_no_err1: Optional["Model2"] # NO ERROR
        mode2_no_err2: "Optional[Model2]" # NO ERROR

class Model2:
    pass

def f():
    class InnerModel1:
        model2: "InnerModel2"
        mode2_err: Optional["InnerModel2"] # ERROR
        mode2_no_err: "Optional[InnerModel2]"

    class InnerModel2:
        pass
```
if I run `pyflakes` against this code I get:

`pyflakes_bug.py:14:29: undefined name 'InnerModel2'`

I would expect that annotating a with `Optional["InnerModel2"]` or with `"Optional[InnerModel2]"` should have the same behaviour as demonstrated with `Optional["Model2"]` and `"Optional[Model2]"`.

Why am I defining a class inside a method?  For now this is supporting lots of unit testing on my side.
