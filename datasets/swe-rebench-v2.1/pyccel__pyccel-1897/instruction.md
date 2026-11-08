Add Python support for dict() function
### Describe the feature
I would like to be able to use the `dict()` function. The `dict()` function is different to the `{}` function as it can behave as a copy function and/or create a dictionary using keyword arguments.

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
if __name__ == '__main__':
    a = dict({1:1.0,2:2.0})
    b = dict(a=1, b=2)
```

### Proposed Solution
This feature should be implemented similarly to what was done for tuples. The equivalent issues for tuples was resolved in #1589.
The pertinent code is:
https://github.com/pyccel/pyccel/blob/d64be7ff7072faa07ce19c9e70fa02ed45a25c9c/pyccel/ast/builtins.py#L596-L620


### Additional context
It is important to handle the `dict` function so that this function can be used for type annotations. If the `{,}` function is used bugs such as #1892 can arise.
