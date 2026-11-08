BUG: Series.replace(dict-like, dict-like) raises uninformative AttributeError
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
In [2]: pd.Series([1, 2]).replace(pd.Series([1]), pd.Series([2]))
AttributeError: 'Series' object has no attribute '_replace_columnwise'
```


### Issue Description

It appears `.replace(dict-like, dict-like)` is only valid if the original object is a `DataFrame` so this should probably raise a `ValueError` instead of raising an `AttributeError`

### Expected Behavior

Raise a `ValueError`

### Installed Versions

<details>

Replace this line with the output of pd.show_versions()

</details>
