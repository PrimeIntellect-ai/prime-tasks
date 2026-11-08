cross_validation doesn't work with SequentialScheme
[HIDDEN] The scheme returns nothing after first epoch.

```python
>>> from fuel.schemes import SequentialScheme, cross_validation

>>> cross = cross_validation(SequentialScheme, 10, 3, False, batch_size=5)
>>> train, valid, valid_size = next(cross)

>>> print list(train.get_request_iterator())
[[3, 4, 5, 6, 7], [8, 9]]
>>> print list(train.get_request_iterator())
[]
```

### Additional contract requirements

- For each cross-validation fold, repeated calls to `get_request_iterator()` on its training and validation iterators must yield the same requests in the same order; consuming an iterator once must not cause a later call to return no requests.
