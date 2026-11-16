`_pseudotreenameclass` as `BaseName` type
```python
Python 3.7.4 (default, Sep 28 2019, 16:39:19)
>>> from jedi import Script
>>> Script('from typing import Any\n').get_names()[0].type
'_pseudotreenameclass'
```

Please consider adding `_pseudotreenameclass` to the valid values list for [`BaseName.type`](https://jedi.readthedocs.io/en/latest/docs/api-classes.html#jedi.api.classes.BaseName.type) or maybe return `class` instead.

Thanks!

### Additional contract requirements

- The required value for `Script('from typing import Any\n').get_names()[0].type` is `'class'`. In parameter-annotation signature output, `Tuple[int]` from `from typing import Tuple\ndef f(x: Tuple[int]): ...\nf` must be represented as `class Tuple` (the expected representation is `['class Tuple']`).
