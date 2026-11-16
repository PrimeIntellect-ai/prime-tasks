`optimize` not lowering fully
```python
import pandas as pd
from dask.dataframe import from_pandas
df = pd.DataFrame(
    {
        "A": [1, 2, 3, 4, 5, 6, 7, 8, 9],
        "B": [9, 8, 7, 6, 5, 4, 3, 2, 1],
        "C": [True, False, True] * 3,
    },
    columns=list("ABC"),
)
ddf = from_pandas(df, 2)
expr = ddf[ddf.C.repartition([0, 2, 5, 8])].expr
expr = expr.optimize()
expr.__dask_graph__()
```

The graph cannot be generated and is running into a `NotImplementedError: Expressions should define either _layer (full dictionary) or _task (single task).  This expression <class 'dask.dataframe.dask_expr._expr.FilterAlign'> defines neither` exception.

The problem arises after the second `simplify` in `optimize_until` which generates another expression that is not fully lowered
