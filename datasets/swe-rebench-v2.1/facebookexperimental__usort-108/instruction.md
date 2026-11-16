compatibility: handle isort:skip on the _first_ line of a wrapped statement
Something like

```
from x import (  # isort:skip
  y,
  z,
)
```

Currently is considered sortable (because it looks for the directive at the end of the _statement_, which here is after the closing paren.  The fix here is probably intertwined with wrapping in #16, and some other libcst or fixit efforts that make edits to change imports.
