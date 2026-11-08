[DICT] Add C support for clear
### Describe the feature
C support should be added for `clear`.

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1,1.0, 2:2.0}
    a.clear()
    return len(a)
```

### Proposed Solution
This should be implemented using [HIDDEN]
