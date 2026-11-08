BUG: pd.unique() does not accept NumpyExtensionArray
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
arr_int = pd.array([1, 2, 3]) # Int64Dtype() => ExtensionArray
arr_complex = pd.array([1+1j, 2, 3]) # NumpyEADtype('complex128') => NumpyExtensionArray

pd.unique(arr_int)  # OK
pd.unique(arr_complex)  # NOK: TypeError: unique requires a Series, Index, ExtensionArray, or np.ndarray, got NumpyExtensionArray.
```


### Issue Description

This issue is similar to #59177 and is coming from `pint-pandas` where test CI job with nightly builds from pandas was recently introduced ([pint-pandas issue related to skipped tests to pass tests with pandas 3](https://github.com/hgrecco/pint-pandas/issues/240)).

The above example is fine with pandas 2.2.2 but fails with pandas nightlies

The above mentionned `TypeError` is coming from https://github.com/pandas-dev/pandas/blob/ab433af410464f4f5c377c82a3d4f5680bf3c65c/pandas/core/algorithms.py#L222

As explained in #59177 `NumpyExtensionArray` may be used internally when other type of `ExtensionArray` are not available.

### Expected Behavior

for pandas 2.2.2 `pd.unique` returns:

``` python
>>> pd.unique(arr_complex)
array([1.+1.j, 2.+0.j, 3.+0.j])
```

While we expect

```python
>>> pd.unique(arr_complex)
<NumpyExtensionArray>
[(1+1j), (2+0j), (3+0j)]
Length: 3, dtype: complex128
```

### Installed Versions

<details>

Replace this line with the output of pd.show_versions()

</details>
