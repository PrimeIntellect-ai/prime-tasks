Deprecate janitor.patterns
janitor.patterns is not really useful (beauty of hindsight :grin: ) , as it is simply a wrapper around `re.compile`, which a user can import and wrap

```py
from re import compile as patterns # or whatever name user prefers
import janitor
import pandas as pd

df.select_columns(patterns('\d+')
```

### Additional contract requirements

Calling `janitor.patterns` continues to work and emits a `DeprecationWarning` recommending `re.compile`. Standard compiled regular-expression patterns created with `re.compile` can be used wherever regular expressions are accepted for selecting columns, including `select_columns` and the regular-expression arguments of `pivot_longer`.
