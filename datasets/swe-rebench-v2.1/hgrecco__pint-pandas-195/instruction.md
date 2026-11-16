pint_pandas won't import using pandas 2.1-dev version
I just tried pint_pandas using the dev version of pandas and got an error:

```python
>>> import pint_pandas
AttributeError: module 'pandas.core.dtypes.dtypes' has no attribute 'PandasDtype'
```

The issue is that pandas has renamed `PandasDtype` to `NumpyEADtype`, see https://github.com/pandas-dev/pandas/pull/54101.
