`RareLabelEncoder` with `missing_values`="ignore" does not work properly with `sklearn.compose.ColumnTransformer`
**Describe the bug**
An exception is raised with for no reason.

**To Reproduce**
```python
  import pandas as pd
  from sklearn.compose import ColumnTransformer
  from feature_engine.encoding import RareLabelEncoder


  input_df = pd.DataFrame(
      {
          "num_col1": [1, 2, 3, 4, 5],
          "num_col2": [1, 2, 3, 4, 5],
          "num_col3": ["1.1", "2.2", "3.3", "4.4", "5.5"],
          "cat_col1": ["A", "A", "A", "B", "B"],
          "cat_col2": ["A", "A", None, "B", "B"],
          "cat_col3": [1, 0, 1, 0, 1],
      }
  )

  ct = ColumnTransformer(
      transformers=[
          (
               "categorical_feat_pipeline",
               RareLabelEncoder(missing_values="ignore"),
               ["cat_col1", "cat_col2", "cat_col3"]
           ),
      ],
  )
  ct.fit(input_df)
```
**Expected behavior**

`RareLabelEncoder` should work as usual.

**Screenshots**
```
/lib/python3.10/site-packages/sklearn/compose/_column_transformer.py:693: in fit
    self.fit_transform(X, y=y)
/lib/python3.10/site-packages/sklearn/utils/_set_output.py:142: in wrapped
    data_to_wrap = f(self, X, *args, **kwargs)
/lib/python3.10/site-packages/sklearn/compose/_column_transformer.py:726: in fit_transform
    result = self._fit_transform(X, y, _fit_transform_one)
/lib/python3.10/site-packages/sklearn/compose/_column_transformer.py:657: in _fit_transform
    return Parallel(n_jobs=self.n_jobs)(
/lib/python3.10/site-packages/joblib/parallel.py:1085: in __call__
    if self.dispatch_one_batch(iterator):
/lib/python3.10/site-packages/joblib/parallel.py:901: in dispatch_one_batch
    self._dispatch(tasks)
/lib/python3.10/site-packages/joblib/parallel.py:819: in _dispatch
    job = self._backend.apply_async(batch, callback=cb)
/lib/python3.10/site-packages/joblib/_parallel_backends.py:208: in apply_async
    result = ImmediateResult(func)
/lib/python3.10/site-packages/joblib/_parallel_backends.py:597: in __init__
    self.results = batch()
/lib/python3.10/site-packages/joblib/parallel.py:288: in __call__
    return [func(*args, **kwargs)
/lib/python3.10/site-packages/joblib/parallel.py:288: in <listcomp>
    return [func(*args, **kwargs)
/lib/python3.10/site-packages/sklearn/utils/fixes.py:117: in __call__
    return self.function(*args, **kwargs)
/lib/python3.10/site-packages/sklearn/pipeline.py:894: in _fit_transform_one
    res = transformer.fit_transform(X, y, **fit_params)
/lib/python3.10/site-packages/sklearn/utils/_set_output.py:142: in wrapped
    data_to_wrap = f(self, X, *args, **kwargs)
/lib/python3.10/site-packages/sklearn/utils/_set_output.py:142: in wrapped
    data_to_wrap = f(self, X, *args, **kwargs)
/lib/python3.10/site-packages/sklearn/utils/_set_output.py:142: in wrapped
    data_to_wrap = f(self, X, *args, **kwargs)
/lib/python3.10/site-packages/sklearn/base.py:848: in fit_transform
    return self.fit(X, **fit_params).transform(X)
/lib/python3.10/site-packages/sklearn/utils/_set_output.py:142: in wrapped
    data_to_wrap = f(self, X, *args, **kwargs)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = RareLabelEncoder(missing_values='ignore'), X =   cat_col1 cat_col2  cat_col3
0        A        A         1
1        A        A         0
2        A     None         1
3        B        B         0
4        B        B         1

    def transform(self, X: pd.DataFrame) -> pd.DataFrame:
        \"""
        Group infrequent categories. Replace infrequent categories by the string 'Rare'
        or any other name provided by the user.

        Parameters
        ----------
        X: pandas dataframe of shape = [n_samples, n_features]
            The input samples.

        Returns
        -------
        X: pandas dataframe of shape = [n_samples, n_features]
            The dataframe where rare categories have been grouped.
        \"""

        X = self._check_transform_input_and_state(X)

        # check if dataset contains na
        if self.missing_values == "raise":
            _check_optional_contains_na(X, self.variables_)

            for feature in self.variables_:
                X[feature] = np.where(
                    X[feature].isin(self.encoder_dict_[feature]),
                    X[feature],
                    self.replace_with,
                )

        else:
            for feature in self.variables_:
                X[feature] = np.where(
>                   X[feature].isin([HIDDEN]),
                    X[feature],
                    self.replace_with,
                )
E               TypeError: can only concatenate str (not "float") to str
```
**Desktop (please complete the following information):**
 - OS: MacOs
 - Version 1.6.0

**Additional context**
Add any other context about the problem here.
