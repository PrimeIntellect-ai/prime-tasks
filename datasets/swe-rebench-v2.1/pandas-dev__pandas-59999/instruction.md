#59745 broke groupby().value_counts with all nan column
              This broke the following case:

```
df = pd.DataFrame({"a": [1, 2, 1, 2], "b": np.nan})
df.groupby("a").value_counts()
```

with

```
Traceback (most recent call last):
  File "/Users/patrick/Library/Application Support/JetBrains/PyCharm2024.1/scratches/scratch_1.py", line 100, in <module>
    df.groupby("a").value_counts()
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/generic.py", line 2723, in value_counts
    return self._value_counts(subset, normalize, sort, ascending, dropna)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/groupby.py", line 2535, in _value_counts
    result_series = cast(Series, gb.size())
                                 ^^^^^^^^^
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/groupby.py", line 2747, in size
    result = self._grouper.size()
             ^^^^^^^^^^^^^^^^^^^^
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/ops.py", line 696, in size
    ids = self.ids
          ^^^^^^^^
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/ops.py", line 750, in ids
    return self.result_index_and_ids[1]
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "properties.pyx", line 36, in pandas._libs.properties.CachedProperty.__get__
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/ops.py", line 769, in result_index_and_ids
    result_index, ids = self._ob_index_and_ids(
                        ^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/patrick/mambaforge/envs/dask-expr/lib/python3.12/site-packages/pandas/core/groupby/ops.py", line 884, in _ob_index_and_ids
    ob_ids = np.where(ob_ids == -1, -1, index.take(ob_ids))
                                        ^^^^^^^^^^^^^^^^^^
IndexError: cannot do a non-empty take from an empty axes.
```

_Originally posted by @phofl in https://github.com/pandas-dev/pandas/issues/59745#issuecomment-2396534876_
