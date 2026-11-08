[SETS] Add C support for `add()`
### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1,2,1}
    a.add(5)
```

### Proposed Solution
This feature should be implemented using the functionalities provided by STC

### Additional contract requirements

- `set.add(element)` is supported for C and Fortran code generation, in addition to Python.
- `set.add(element)` inserts `element` into the set if it is not already present, and leaves the set unchanged if it is already present.
- `set.add(element)` mutates the set in place.
