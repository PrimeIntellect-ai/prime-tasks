`timeseries()` on empty `IamDataFrame` fails very loudly
# Description of the issue

When calling `timeseries()` on an empty `IamDataFrame`, the internally used `pandas.DataFrame.pivot_table()` fails with a long, non-intuitive error message (see below). This might be quite intimidating to non-expert users.

## Improved behaviour

[HIDDEN]

Two questions on implementation and expected behaviour, though:

1) Should `pyam` only write a message to the log file (as is done for `filter()`, see [here](https://github.com/IAMconsortium/pyam/blob/103b60f8f2f46fddae4d0325cbc2651cb098030a/pyam/core.py#L1001), or should a (nicer) error be raised?

2) If only a warning is written to the log, should the returned object be `None` or an empty `pandas.DataFrame` (but with the correct index dimensions).

# Error message

```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-48-36a29f3c3d4a> in <module>
----> 1 df.filter(variable='foo').timeseries()

~/Github/pyam/pyam/core.py in timeseries(self, iamc_index)
    382         df = (
    383             self.data
--> 384             .pivot_table(index=index, columns=self.time_col)
    385             .value  # column name
    386             .rename_axis(None, axis=1)

~/anaconda3/lib/python3.7/site-packages/pandas/core/generic.py in __getattr__(self, name)
   5177             if self._info_axis._can_hold_identifiers_and_holds_name(name):
   5178                 return self[name]
-> 5179             return object.__getattribute__(self, name)
   5180
   5181     def __setattr__(self, name, value):

AttributeError: 'DataFrame' object has no attribute 'value'
```

### Additional contract requirements

- `IamDataFrame` (in module `pyam.core`) exposes a public property `empty` that is `True` exactly when the frame holds no data rows, and `False` otherwise.
- `IamDataFrame.timeseries()` raises a `ValueError` with the message `this \`IamDataFrame\` is empty` when it is called on an empty `IamDataFrame`.
