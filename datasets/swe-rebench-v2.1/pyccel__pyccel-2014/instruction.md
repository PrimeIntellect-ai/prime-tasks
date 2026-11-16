[SETS] Add Fortran support for pop()
### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1,2,1}
    b = a.pop()
    c = a.pop()
    return b,c
```

### Proposed Solution
This feature should be implemented using gFTL. Unfortunately the gFTL implementation of sets does not appear to be very developed for the moment so this issue will probably require a corresponding issue and maybe PR in gFTL.
