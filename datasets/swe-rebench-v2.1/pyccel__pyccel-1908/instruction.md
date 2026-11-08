[SETS] Add C support for len function
### Describe the feature
In Python the len function can be called on many functions however the implementation of this function is different in different languages. Support should be added to test the length of a list in C (and Python if it does not work out of the box).

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def f():
    a = {1,2,1}
    b = len(a)
    return b
```

### Proposed Solution
This feature should be implemented using the functionalities provided by STC

### Additional contract requirements

The `len` builtin must also work for sets in both C and Python. Its result is the number of distinct members, so repeated values contribute only once.
