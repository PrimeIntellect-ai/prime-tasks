BUG: Inconsistent dtype with GroupBy for StrDtype and all missing values
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
>>> df = pd.DataFrame({"a": ["a"] * 3, "b": pd.Series([None] * 3, dtype=pd.StringDtype(na_value=np.nan))})
>>> df
   a    b
0  a  NaN
1  a  NaN
2  a  NaN
>>> df.groupby("a").sum()
   b
a
a  0
>>> df.groupby("a").sum().dtypes
b    str
dtype: object
>>> df.groupby("a").min()
    b
a
a NaN
>>> df.groupby("a").min().dtypes
b    float64
dtype: object
```

### Issue Description

The sum reduction return type is partially discussed in https://github.com/pandas-dev/pandas/issues/60229 but I didn't see anything for `min`

Note that this discrepancy is the root cause of the test failure shown at https://github.com/pandas-dev/pandas/blob/dec6eb29b35c884e78c82525e1bb30280208714c/pandas/tests/resample/test_resampler_grouper.py#L465

@rhshadrach

### Expected Behavior

I think in all cases here we should still be returning a `str` type.

### Installed Versions

'3.0.0.dev0+1824.g8d6d29cac3.dirty'
