`attr.resolve_types` caches badly with inheritence
Reproduction case:

```py
from __future__ import annotations

import attr

@attr.define()
class A:
  n: int

@attr.define()
class B(A):
  pass

attr.resolve_types(A)
attr.resolve_types(B)

print(attr.fields(B))
```

[HIDDEN]

This came up when I was using cattrs (I raised an issue there about a trouble I had debugging too :^), which means I do not control the resolution order of types without applying a `attr.resolve_types` decorator to every class (which might not work -- I'm not sure all my class declarations are in order either...)

### Additional contract requirements

- After `attr.resolve_types` has been called on a parent class, calling it on a subclass must still resolve that subclass’s inherited field annotations. `attr.fields(subclass)` must report the resolved types for those fields.
