IndexError: positional indexers are out-of-bounds
### Reproducer

Note: the example below works when `n_rows` is small

```
import evalml
import pandas as pd
automl = evalml.AutoMLSearch(problem_type="binary")

n_rows = 1000000
X = pd.DataFrame({"f_1": [1, 2, 3]*n_rows})
X.index = pd.Series(range(X.shape[0])) + 1
y = pd.Series([True, False, True]*n_rows)

automl.search(X, y, data_checks='disabled')
```

this give the follow stacktrace

```
---------------------------------------------------------------------------
IndexError                                Traceback (most recent call last)
~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/indexing.py in _get_list_axis(self, key, axis)
   2110         try:
-> 2111             return self.obj._take_with_is_copy(key, axis=axis)
   2112         except IndexError:

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/generic.py in _take_with_is_copy(self, indices, axis, **kwargs)
   3408         """
-> 3409         result = self.take(indices=indices, axis=axis, **kwargs)
   3410         # Maybe set copy if we didn't actually change the index.

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/generic.py in take(self, indices, axis, is_copy, **kwargs)
   3394         new_data = self._data.take(
-> 3395             indices, axis=self._get_block_manager_axis(axis), verify=True
   3396         )

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/internals/managers.py in take(self, indexer, axis, verify, convert)
   1385         if convert:
-> 1386             indexer = maybe_convert_indices(indexer, n)
   1387

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/indexers.py in maybe_convert_indices(indices, n)
    212     if mask.any():
--> 213         raise IndexError("indices are out-of-bounds")
    214     return indices

IndexError: indices are out-of-bounds

During handling of the above exception, another exception occurred:

IndexError                                Traceback (most recent call last)
<ipython-input-24-2d762c4df3d4> in <module>
      8 y = pd.Series([True, False, True]*n_rows)
      9
---> 10 automl.search(X, y, data_checks='disabled')

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/evalml/automl/automl_search.py in search(self, X, y, data_checks, feature_types, show_iteration_plot)
    410         self._start = time.time()
    411
--> 412         should_terminate = self._add_baseline_pipelines(X, y)
    413         if should_terminate:
    414             return

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/evalml/automl/automl_search.py in _add_baseline_pipelines(self, X, y)
    543                                 self._start)
    544
--> 545                 baseline_results = self._compute_cv_scores(baseline, X, y)
    546                 self._baseline_cv_score = baseline_results["cv_score_mean"]
    547                 self._add_result(trained_pipeline=baseline,

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/evalml/automl/automl_search.py in _compute_cv_scores(self, pipeline, X, y)
    563         for i, (train, test) in enumerate(self.data_split.split(X, y)):
    564             logger.debug(f"\t\tTraining and scoring on fold {i}")
--> 565             X_train, X_test = X.iloc[train], X.iloc[test]
    566             y_train, y_test = y.iloc[train], y.iloc[test]
    567             objectives_to_score = [self.objective] + self.additional_objectives

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/indexing.py in __getitem__(self, key)
   1766
   1767             maybe_callable = com.apply_if_callable(key, self.obj)
-> 1768             return self._getitem_axis(maybe_callable, axis=axis)
   1769
   1770     def _is_scalar_access(self, key: Tuple):

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/indexing.py in _getitem_axis(self, key, axis)
   2127         # a list of integers
   2128         elif is_list_like_indexer(key):
-> 2129             return self._get_list_axis(key, axis=axis)
   2130
   2131         # a single integer

~/.pyenv/versions/3.6.9/envs/tmp-install/lib/python3.6/site-packages/pandas/core/indexing.py in _get_list_axis(self, key, axis)
   2112         except IndexError:
   2113             # re-raise with different error message
-> 2114             raise IndexError("positional indexers are out-of-bounds")
   2115
   2116     def _getitem_axis(self, key, axis: int):

IndexError: positional indexers are out-of-bounds
```


### workaround

This works

```
automl.search(X.reset_index(), y, data_checks='disabled')
```

### Notes

This seems to only occur once the data is above a certain number of rows, so i suspect it has to do with the different data splitter we use in that case

### Additional contract requirements

- `TrainingValidationSplit` is importable from `evalml.automl`.
- `TrainingValidationSplit.split(self, X, y=None)` returns a list containing a single tuple `(train_indices, test_indices)`.
- Each of `train_indices` and `test_indices` is a NumPy array of integer positions in the range `[0, len(X) - 1]`.
- The returned positions are valid zero-based positional indices even when `X` has a custom (non-default) DataFrame index.
- The split honors the configured `test_size`, `train_size`, `shuffle`, `stratify`, and `random_state` parameters.
