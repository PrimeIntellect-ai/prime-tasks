RDT NullTransformer doesn't replace nulls if missing_value_generation is None
### Environment Details

Please indicate the following details about the environment in which you found the bug:

* RDT version: 1.5.0
* Python version: Any
* Operating System: Any

### Error Description

When setting the `missing_value_generation` to None and the `missing_value_replacement` to 'mean', I would expect the forward transform to impute the nans with the mean value. Instead it currently does nothing. This is because of the following line:
https://github.com/sdv-dev/RDT/blob/3970e4028af4fa5d519c8a1cf997c7d874c5bf97/rdt/transformers/null.py#L129

### Steps to reproduce

```python
data = pd.Series([1, 2, np.nan, 3])
nt = NullTransformer(missing_value_replacement='mean', missing_value_generation=None)
nt.fit(data)
nt.transform(data)
```
