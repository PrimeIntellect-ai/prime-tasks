[DICT] Add C support for pop
### Describe the feature
Add C support for the dict method `pop`.

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1:1.0, 2:2.0}
    b = a.pop(1)
    c = a.pop(3, 4.0)
    return len(a), b, c
```

### Proposed Solution
This should be implemented using the hmap_X_erase method documented here:
https://github.com/stclib/STC/blob/master/docs/hmap_api.md
