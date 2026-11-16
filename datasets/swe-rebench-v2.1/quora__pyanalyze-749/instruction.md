Incorrect "possibly_undefined_name" with walrus operator
```
% cat ~/Desktop/walrus.py
from typing_extensions import assert_type


def f() -> int:
    return 3


def g(cond: bool) -> None:
    if cond and (x := f()):
        assert_type(x, int)
% python -m pyanalyze ~/Desktop/walrus.py  -e possibly_undefined_name

x may be used uninitialized (code: possibly_undefined_name)
In /Users/jelle/Desktop/walrus.py at line 10
   7:
   8: def g(cond: bool) -> None:
   9:     if cond and (x := f()):
  10:         assert_type(x, int)
                          ^

Type is Union[Any[error], int] (expected int) (code: inference_failure)
In /Users/jelle/Desktop/walrus.py at line 10
   7:
   8: def g(cond: bool) -> None:
   9:     if cond and (x := f()):
  10:         assert_type(x, int)
              ^
```

### Additional contract requirements

- For `if cond and (x := 1):`, `x` in the body must retain the type `Literal[1]`, so `assert_type(x, Literal[1])` passes.
