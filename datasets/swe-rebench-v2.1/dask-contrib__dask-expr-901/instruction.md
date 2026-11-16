RecursionError after assigning empty list of columns
Ran into this during some unittesting. Although a bit odd, this code runs fine with query-planning disabled
```python
import dask
dask.config.set({'dataframe.query-planning': False})
import dask.dataframe as dd
import pandas as pd

ddf = dd.from_pandas(pd.DataFrame({'a': [1]}), npartitions=1)
print(ddf.columns)
ddf[[]] = ddf[[]].astype(str)
print(ddf.columns)
```
>Index(['a'], dtype='object')
>Index(['a'], dtype='object')

But with query-planning enabled, it throws a recursion error when trying to access the columns the second time.
```python
import dask
dask.config.set({'dataframe.query-planning': True})
import dask.dataframe as dd
import pandas as pd

ddf = dd.from_pandas(pd.DataFrame({'a': [1]}), npartitions=1)
print(ddf.columns)
ddf[[]] = ddf[[]].astype(str)
print(ddf.columns)
```
>Index(['a'], dtype='object')
Traceback (most recent call last):
  File ".../dev.py", line 9, in <module>
    print(ddf.columns)
  File ".../python3.10/site-packages/dask_expr/_collection.py", line 350, in columns
    return self._meta.columns
  File ".../python3.10/site-packages/dask_expr/_collection.py", line 297, in _meta
    return self.expr._meta
  File ".../python3.10/site-packages/dask_expr/_collection.py", line 297, in _meta
    return self.expr._meta
  File ".../python3.10/site-packages/dask_expr/_collection.py", line 297, in _meta
    return self.expr._meta
  [Previous line repeated 995 more times]
RecursionError: maximum recursion depth exceeded

Versions:
* dask == 2024.2.1
* dask-expr == 0.5.2
* pandas == 2.1.4
