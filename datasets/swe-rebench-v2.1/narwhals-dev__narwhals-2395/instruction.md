[Bug]: `is_numpy_scalar` reeturns `True` for non-numpy scalars
### Describe the bug

The function signature of `narwhals.dependencies.is_numpy_scalar` says that it narrows the type to `np.generic`m but it is not necessarily the case, as `numpy.is_scalar` also returns `True` for Python scalars. A potential fix would be to [HIDDEN]

Also, a related question: is `is_numpy_scalar` considered to be a part of the public API? I don't think it's in the docs, but I think it could be useful.

### Steps or code to reproduce the bug

```python
import numpy as np
from narwhals.dependencies import is_numpy_scalar

isinstance(1, np.generic)  # False
is_numpy_scalar(1)  # True, but should be False
```

### Expected results

`is_numpy_scalar(x) == True` should imply `isinstance(x, np.generic) == True`.

### Actual results

It does not for Python scalars (see example).

### Please run narwhals.show_version() and enter the output below.

```shell
System:
    python: 3.13.3 | packaged by conda-forge | (main, Apr 14 2025, 20:44:30) [Clang 18.1.8 ]
executable: /Users/stanmart/Library/Caches/rattler/cache/cached-envs-v0/ipython-c454637721dc3b0a/bin/python3.13
   machine: macOS-15.4-arm64-arm-64bit-Mach-O

Python dependencies:
     narwhals: 1.35.0
       pandas:
       polars:
         cudf:
        modin:
      pyarrow:
        numpy: 2.2.4
```

### Relevant log output

```shell

```
