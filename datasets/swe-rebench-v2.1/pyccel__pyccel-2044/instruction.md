[DICT] Add Python support for copy
### Describe the feature
Syntactic and semantic support should be added for `copy`. This should be tested by implementing Python printing

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1,1.0, 2:2.0}
    b = a.copy()
    return b
```

### Additional contract requirements

Calling `copy()` on a dictionary returns a distinct dictionary containing the same entries. The copy is shallow: it does not recursively copy the values.
