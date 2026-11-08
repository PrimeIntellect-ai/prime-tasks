[DICT] Add Python support for keys
### Describe the feature
Syntactic and semantic support should be added for `keys`. This should be tested by implementing Python printing

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1,1.0, 2:2.0}
    b : list[int] = []
    for bi in a.keys():
        b.append(bi)
    return b
```
