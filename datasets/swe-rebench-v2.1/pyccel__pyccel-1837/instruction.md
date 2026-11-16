Tuple incorrectly identified as inhomogeneous
### Describe the bug
Tuples are occasionally misidentified as being inhomogeneous. This prevents them from being indexed.

### To Reproduce
Provide code to reproduce the behavior:
```python
def homogeneous_tuple_containing_var():
    elem = 4
    ai = (1, elem, 5)
    i = 1
    return ai[0], ai[i], ai[2]
```

### Error details
Provide the generated code, or the error message:
```
ERROR at annotation (semantic) stage
pyccel:
 |fatal [semantic]: tmp_idx.py [5,18]| Inhomogeneous tuples must be indexed with constant integers for the type inference to work (ai)
```

### Additional context
Found while cleaning up tuples in #1838
