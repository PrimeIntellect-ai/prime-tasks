[DICT] Add Python support for pop
### Describe the feature
Syntactic and semantic support should be added for `pop`. This should be tested by implementing Python printing

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def foo():
    a = {1:1.0, 2:2.0}
    b = a.pop(1)
    c = a.pop(3, 4.0)
    return a, b, c
```

### Additional contract requirements

When `pop` is called with a key that is absent and no default value, it raises `KeyError`.
