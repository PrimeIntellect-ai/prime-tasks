Implement valid_datetime metadata key
### Is your feature request related to a problem? Please describe.

In GRIB data there is no single valid datetime key available, but this piece of information has to be constructed from multiple keys, e.g. from `validityDate` and `validityTime`. At the moment, valid datetime is only available on a GRIB field via the `datetime` method as:

```python
myfield.datetime()["valid_time"]
```

The suggestion is to implement the `valid_datetime` metadata key so that we can access valid datetime as:

```python
myfield.metadata("valid_datetime")
```

This key then could be used in methods like `sel` and `order_by`:


```python
myfieldlist.order_by(valid_datetime="ascending")
```

### Describe the solution you'd like

_No response_

### Describe alternatives you've considered

_No response_

### Additional context

_No response_

### Organisation

ECMWF

### Additional contract requirements

- The `valid_datetime` metadata key is available through metadata access on GRIB fields, NetCDF fields, and in-memory GRIB fields created with the `list-of-dicts` source.
- Metadata values are read with `metadata["key"]` and `metadata.get("key", default=None)`. A missing key raises `KeyError` through `metadata["key"]` and yields the default through `metadata.get`.
- For in-memory GRIB fields created with the `list-of-dicts` source, metadata lookup accepts the alias `param` for `shortName` and `_param_id` for `paramId`, accepts `date` for `dataDate`, `time` for `dataTime`, `level` for `levelist` and `step` for `endStep`/`stepRange`, and accepts a type suffix `:s`, `:l`, `:d`, `:str`, `:int` or `:float` to convert the value.
