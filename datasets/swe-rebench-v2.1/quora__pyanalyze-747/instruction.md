pyanalyze doesn't narrow isinstance(..., Mapping)
```
from typing import Any, Mapping

class A: ...
def takes_mapping(x: Mapping[str, Any]) -> None: ...

def foo(x: A | Mapping[str, Any]) -> None:
    if isinstance(x, Mapping):
        takes_mapping(x)
```
gives:
```
Incompatible argument type for x: expected collections.abc.Mapping[str, Any[explicit]] but got Union[/Users/shantanu/devoai/openai/b.py.A, collections.abc.Mapping[str, Any[explicit]]] (code: incompatible_argument)
  Cannot assign /Users/shantanu/devoai/openai/b.py.A to collections.abc.Mapping

In b.py at line 8
   5:
   6: def foo(x: A | Mapping[str, Any]) -> None:
   7:     if isinstance(x, Mapping):
   8:         takes_mapping(x)
```
