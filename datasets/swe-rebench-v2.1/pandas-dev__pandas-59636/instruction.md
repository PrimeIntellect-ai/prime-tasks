BUG: binary operations don't propogate attrs depending on order with Series and/or DataFrame/Series
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
In [1]: ser1 = pd.Series(range(1))

In [2]: ser2 = pd.Series(range(1))

In [3]: ser1.attrs = {1:2}

In [4]: val = ser2 + ser1

In [5]: val.attrs
Out[5]: {}
```


### Issue Description

`val.attrs` should be `{1:2}`

The relevant tests are xfailed in `test_finalize.py::test_binary`

### Expected Behavior

`val.attrs` should be `{1:2}`

### Installed Versions

<details>

Replace this line with the output of pd.show_versions()

</details>
