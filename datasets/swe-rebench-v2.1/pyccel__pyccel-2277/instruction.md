[DICTS] Support dicts as results in Fortran
### Describe the feature
Support returning dicts from Fortran code

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def f():
    a = {1:1.0}
    return a
```

### Proposed Solution
The cwrapper should be improved to ensure that dicts can be read from Fortran code and passed to Python.
