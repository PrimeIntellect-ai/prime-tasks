`Locale.get_display_name` raises a cryptic `TypeError` with valid args
# Overview Description

`Locale.get_display_name` raises a cryptic `TypeError` with valid args.

# Steps to Reproduce

1. Create environment with python3.6 and babel-2.6.0
2. Run

```
from babel.core import Locale
Locale.parse('fi_FI').get_display_name('kw_GB')
```

# Actual Results
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/will/tmp/babel-bug/env/lib/python3.6/site-packages/babel/core.py", line 392, in get_display_name
    retval += ' (%s)' % u', '.join(details)
TypeError: unsupported operand type(s) for +=: 'NoneType' and 'str'
```

# Expected Results

Some interpretation of "Finish (Finland)"

# Reproducibility

Yes

### Additional contract requirements

- When the language name is unavailable, `Locale.get_display_name` should return `None` rather than raise an exception. The reproduced call must not raise a `TypeError`.
