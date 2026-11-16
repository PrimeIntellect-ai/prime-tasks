Initialize Series with tuple of nans fails
Initializing a series with a tuple of nans fails.


#### Code Sample

```python
ww.init_series(pd.Series([(1.0, 2.0), (float('nan'), float('nan'))]), logical_type='LatLong')
```

Returns this error
```
ValueError: Cannot initialize Woodwork. Series does not contain properly formatted LatLong data. Try reformatting before initializing or use the woodwork.init_series function to initialize.
```

### Additional contract requirements

- `woodwork.utils._reformat_to_latlong(latlong, is_koalas=False)` normalizes a LatLong value. A 2-tuple or 2-list of numeric or null-like components, or a string representation of one, becomes a tuple `(latitude, longitude)` of floats, with null-like components represented as `np.nan`. A single null-like value becomes `np.nan`. When `is_koalas=True` the pair is returned as a list `[latitude, longitude]` instead of a tuple. It raises `woodwork.exceptions.TypeValidationError` when the value is not a recognized LatLong format, does not contain exactly two elements, or contains components that cannot be converted to floats.
- `woodwork.utils._coerce_to_float(val)` returns the `float` value of a numeric or stringified-numeric scalar, returns `np.nan` for null-like values (`None`, `np.nan`, `pd.NA`), and raises `ValueError` when the value cannot be converted to a float.
- `woodwork.utils._is_valid_latlong_value(val, is_koalas=False)` returns `True` when `val` is a 2-tuple of floats (or a 2-list of floats when `is_koalas=True`) or a single float NaN, and `False` otherwise.
- `woodwork.exceptions.TypeValidationError` is the exception type raised for invalid LatLong input.
