Accept IntEnum as float
```py
import enum

class A(enum.IntEnum):
    a = 1
    b = 2
    c = 3

def f(arg: int) -> None:
    ...

f(A.c)  # IntEnum -> int: ok


def g(arg: float) -> None:
    ...

a: int = 100
g(a)  # int -> float : ok
g(A.b)  # IntEnum -> float : incompatible_argument
```

```
Incompatible argument type for arg: expected float but got Literal[<A.b: 2>] (code: incompatible_argument)
  Cannot assign Literal[<A.b: 2>] to float
```

Should we accept IntEnum as float? mypy is fine with this.
