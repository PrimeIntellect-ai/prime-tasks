Add support for strings as arguments
### Describe the feature
It should be possible to pass strings as arguments to functions

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
def f(option : str):
    if option == 'do this':
        return 1.0
    else:
        return 2.0
```

### Proposed Solution
Most of the tools necessary for this should already be implemented. The main missing piece is the wrapping

### Additional context
This feature was requested by @spossann for Struphy
