[BUG] Extend `fill_empty`'s `column_names` type range
# Brief Description

<!-- Please provide a brief description of your bug. Do NOT paste the stack trace here. -->

https://github.com/pyjanitor-devs/pyjanitor/blob/3fab49e8c89f1a5e4ca7a6e4fdbbe8e2f7b89c66/janitor/functions/fill.py#L148-L152

Quickly fix this, could add `pd.Index`.

And a little bit more thinking, using `Iterable` is better?
Because `check_column`'s `column_names` also support `Iterable`.
And `pd.Index`'s instance is also `Iterable`.
[HIDDEN]

# Minimally Reproducible Code

<!-- If you provide minimal code that reproduces the problem, this makes it easier for us to debug what's going on.

Minimal code should be trivially copy/pastable into a Python interpreter in its entirety. Be sure to include imports.
-->

```python
>>> import pandas as pd
>>> import janitor  # noqa

>>> df = pd.DataFrame({"attr":[None, None]})
>>> df.fill_empty(df.columns, 0)
Traceback (most recent call last):
  File "C:\Software\miniforge3\envs\work\lib\site-packages\multipledispatch\dispatcher.py", line 269, in __call__
    func = self._cache[types]
KeyError: (<class 'pandas.core.frame.DataFrame'>, <class 'pandas.core.indexes.base.Index'>)

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "C:\Software\miniforge3\envs\work\lib\site-packages\pandas_flavor\register.py", line 29, in __call__
    return method(self._obj, *args, **kwargs)
  File "C:\Software\miniforge3\envs\work\lib\site-packages\janitor\utils.py", line 231, in wrapper
    return func(*args, **kwargs)
  File "C:\Software\miniforge3\envs\work\lib\site-packages\janitor\functions\fill.py", line 199, in fill_empty
    return _fill_empty(df, column_names, value=value)
  File "C:\Software\miniforge3\envs\work\lib\site-packages\multipledispatch\dispatcher.py", line 273, in __call__
    raise NotImplementedError(
NotImplementedError: Could not find signature for _fill_empty: <DataFrame, Index>
```

### Additional contract requirements

- `fill_empty` must accept an iterable of column labels for `column_names`, including a pandas `Index`, and apply its existing fill behavior to the selected columns.
