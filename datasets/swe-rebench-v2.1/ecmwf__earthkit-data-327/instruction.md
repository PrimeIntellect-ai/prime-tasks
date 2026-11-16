Allow None for  bits_per_value option in FieldList save() method
### Is your feature request related to a problem? Please describe.

Currently `save()` has the following options:

```python
def save(filename, append=False, check_nans=True, bits_per_value=16)
```
where `bits_per_value` must be an int (cannot be None).

This poses a problem when the Fieldlist was created by modifying another one, and we want keep the original fields' `bits_per_value` settings.

The simplest solution would be to allow `bits_per_value=None`, which would indicate to keep the original settings.

As for the default value, we should use:

```python
bits_per_value=None
```

### Describe the solution you'd like

_No response_

### Describe alternatives you've considered

_No response_

### Additional context

_No response_

### Organisation

_No response_
