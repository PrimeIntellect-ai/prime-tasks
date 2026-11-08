Add input validation to ww.init_series
The `init_series` function added as part of the accessor update does not validate that the input passed in for the series is a valid series type. If the user passes in a non-series object an error is currently raised, but the error message is not helpful in understanding what went wrong.  Current behavior:
```python
>>> ww.init_series(3)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/nate.parsons/dev/woodwork/woodwork/accessor_utils.py", line 38, in init_series
    logical_type = _get_column_logical_type(series, logical_type, series.name)
AttributeError: 'int' object has no attribute 'name'
```

We should add a validation check to this function and raise a better error if improper inputs are supplied.

### Additional contract requirements

- For an invalid input, raise a `TypeError` with the message `Input must be of series type. The current input is of type {type(series)}`, replacing `{type(series)}` with the input's Python type representation.
