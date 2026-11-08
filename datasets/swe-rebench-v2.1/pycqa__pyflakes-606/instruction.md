Odd edge-case regression in type annotated `__all__`
I'm not quite sure how to approach fixing this -- it regressed as part of #535 -- CC @srittau

Here's a simplified example, this is boiled down from numpy's `numpy/typing/__init__.py`

```python
from typing import TYPE_CHECKING, List

from y import z

if not TYPE_CHECKING:
    __all__ = ("z",)
else:
    __all__: List[str]
```

After #535, the type annotation clobbers the `__all__` [HIDDEN] which causes it to no longer mark the imports as used

[HIDDEN]

### Additional contract requirements

- When `__all__` is assigned in one control-flow branch and annotated without an assignment in another, the annotation must not discard the existing export binding. Names listed in `__all__` must continue to count as used.
