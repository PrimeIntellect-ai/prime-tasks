API: behaviour for the "str.center()" string method for the pyarrow-backed string dtype
From https://github.com/pandas-dev/pandas/pull/54533#discussion_r1299808126 (and relevant for new String dtype https://github.com/pandas-dev/pandas/issues/54792)

In general the pyarrow backed string dtype is meant to behave the same as the existing object-dtype or non-pyarrow backed StringDtype, so users in generally should have a smooth way of upgrading. In general most string compute functions in pyarrow have similar behaviour, or we still have a few places where we fall back to the original object-based methods.

One specific method that currently has a different behaviour is `str.center`:

```python
>>> pd.Series(["a", "bb", "cccc"], dtype="object").str.center(5, fillchar="X")
0    XXaXX
1    XXbbX
2    Xcccc
dtype: object

>>> pd.Series(["a", "bb", "cccc"], dtype="string[python]").str.center(5, fillchar="X")
0    XXaXX
1    XXbbX
2    Xcccc
dtype: string

>>> pd.Series(["a", "bb", "cccc"], dtype="string[pyarrow]").str.center(5, fillchar="X")
0    XXaXX
1    XXbbX
2    Xcccc
dtype: string

>>> pd.Series(["a", "bb", "cccc"], dtype="string[pyarrow_numpy]").str.center(5, fillchar="X")
0    XXaXX
1    XbbXX    # <-- aligned left instead of right
2    ccccX    # <-- aligned left instead of right
dtype: string
```

The first three dtypes all give the same result, but for the last one using `StringDtype(storage="pyarrow_numpy")`, the strings are "aligned" to the left instead of right in case an uneven fill chars have to be used.

This is a behaviour we inherited from the Python `str` center method, but the pyarrow `pyarrow.compute.ascii_center` function apparently made the opposite choice (I don't think was necessarily an intentional choice to deviate from this; there was no discussion about this on the PR (https://github.com/apache/arrow/pull/10586), which did add the comment *"If odd number of spaces, put the extra space on the left"* to the relevant place in the code that handles this).

This is a potentially breaking change for users, so to start with should decide if we want to keep the current behaviour or not for the future string dtype. [HIDDEN]

### Additional contract requirements

- For pyarrow-backed string dtypes, `str.center` must distribute fill characters as Python `str.center` does, matching object and non-pyarrow `StringDtype` behavior. When the required padding is uneven, the extra fill character goes on the left.
