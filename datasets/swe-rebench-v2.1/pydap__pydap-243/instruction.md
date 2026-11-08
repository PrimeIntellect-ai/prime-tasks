Deprecations about imports from collections
The `Mapping` import causes a deprecation warning and will be removed in 3.9:
```
.../pydap/model.py:175
  .../pydap/model.py:175: DeprecationWarning: Using or importing the ABCs from 'collections' instead of from 'collections.abc' is deprecated, and in 3.8 it will stop working
    [HIDDEN]
```
Also, `Iterable`:
```
.../pydap/responses/das.py:14
  .../pydap/responses/das.py:14: DeprecationWarning: Using or importing the ABCs from 'collections' instead of from 'collections.abc' is deprecated, and in 3.8 it will stop working
    [HIDDEN]
```

### Additional contract requirements

- The `Mapping` and `Iterable` imports must avoid deprecation warnings for importing ABCs from `collections` and remain compatible with Python versions where those names are no longer available there.
