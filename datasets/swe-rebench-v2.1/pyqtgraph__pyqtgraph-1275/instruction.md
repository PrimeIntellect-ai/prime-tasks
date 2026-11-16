Parameter: hasDefault() always returns true after initializing a new Parameter even without passing in default value (and potential fix for this in comments)
I recently ran into an issue when trying to instantiate Parameter objects with and without default parameters. I include the description of the issue and a potential solution below.

I used these two dictionaries to create new Parameter objects:

```python
{'name': 'stick', 'type': 'int', 'value':1., 'default':None, 'title': "stick"},
{'name': 'file_name', 'type': 'str', 'title': "filename"}
```

When I created new Parameters with these dictionaries, both Parameters returned True for hasDefault(). I looked into the code of Parameter and found these two snippets:

```python
def __init__(self, **opts):
     .
     .
     .
    if 'default' not in self.opts:
              self.opts['default'] = None
              self.setDefault(self.opts['value'])
```

```python
def hasDefault(self):
        """Returns True if this parameter has a default value."""
        return 'default' in self.opts
```

In the initialization it sets self.opts['default'] to None if there is no default passed in so _hasDefault will always return True regardless of if a default is given by the user._

[HIDDEN]

```python
def __init__(self, **opts):
     .
     .
     .
     [HIDDEN]
```

```python
def hasDefault(self):
        """Returns True if this parameter has a default value."""
        [HIDDEN]
```

```python
def setDefault(self, val):
        """Set the default value for this parameter."""
        [HIDDEN]
```

There would have to be some more changes since some other functions expect a default value. If you would like, I would be happy to add this in a branch and make a pull request.

### Additional contract requirements

- Treat `default=None` as no default: `hasDefault()` must return `False` whether `default` is omitted or explicitly set to `None`, `defaultValue()` must return `None` in either case, and calling `setDefault(None)` must leave `hasDefault()` as `False`.
- `hasDefault()` must return `True` when a non-`None` default is supplied at construction.
- Calling `setDefault()` with a non-`None` value must establish that value as the default, make `hasDefault()` return `True`, and make the value available through `defaultValue()`.
