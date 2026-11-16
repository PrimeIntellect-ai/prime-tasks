ENH: pd.Timedelta could issue warning when 'units' falls through to **kwargs
### Feature Type

- [ ] Adding new functionality to pandas

- [X] Changing existing functionality in pandas

- [ ] Removing existing functionality in pandas


### Problem Description

When using pandas `pd.Timedelta` function, if the `unit` keyword is mis-typed as `units`, then no error or warning is raised (I assume as it's passed down through **kwargs to datetime.timedelta).

So for example `pd.Timedelta(1, unit='hours')` returns `Timedelta('0 days 01:00:00')`. All good there. But if a user were to misremember the keyword and instead foolishly type in `pd.Timedelta(1, units='hours')` no warning will be raised, but default units of nano-seconds will be used and this will return: `Timedelta('0 days 00:00:00.000000001')`.

This is clearly user-error (they could read the correct spelling of the keyword in the docs) - and is perhaps unreasonable feature to request, but can result in quite subtle bugs - as the type returned is correct, but of a very different size to that expected.

### Feature Description

The list of available kwargs is quite short https://pandas.pydata.org/docs/reference/api/pandas.Timedelta.html - so could add a check that there aren't any others sneaking through, and raise a warning if so.

### Alternative Solutions

Expect users not to mis-spell keywords :)

### Additional Context

_No response_

### Additional contract requirements

When `pd.Timedelta` is called with a value and an unsupported keyword argument, it must raise `ValueError` instead of constructing a duration using the default unit.
