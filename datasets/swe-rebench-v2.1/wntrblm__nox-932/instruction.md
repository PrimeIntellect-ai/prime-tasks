nox 2025.02.09 doesn't like `nox.options.envdir` to be a `pathlib.Path`
### Current Behavior

This used to work in older nox releases but breaks in `2025.02.09`:
```python
File "/__w/foobar/noxfile.py", line 66, in <module>
    nox.options.envdir = Path(".venv")
    ^^^^^^^^^^^^^^^^^^
  File "/github/home/.local/share/pipx/venvs/nox/lib/python3.12/site-packages/attr/_make.py", line 1119, in __setattr__
    nval = hook(self, a, val)
           ^^^^^^^^^^^^^^^^^^
  File "/github/home/.local/share/pipx/venvs/nox/lib/python3.12/site-packages/attr/setters.py", line 22, in wrapped_pipe
    rv = setter(instance, attrib, rv)
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/github/home/.local/share/pipx/venvs/nox/lib/python3.12/site-packages/attr/setters.py", line [51](github_url/12345#step:17:52), in validate
    v(instance, attrib, new_value)
  File "/github/home/.local/share/pipx/venvs/nox/lib/python3.12/site-packages/attr/validators.py", line 206, in __call__
    self.validator(inst, attr, value)
  File "/github/home/.local/share/pipx/venvs/nox/lib/python3.12/site-packages/attr/validators.py", line 100, in __call__
    raise TypeError(
TypeError: ("'envdir' must be <class 'str'> (got PosixPath('.venv') that is a <class 'pathlib.PosixPath'>).", Attribute(name='envdir', default=NOTHING, validator=<optional validator for <instance_of validator for type <class 'str'>> or None>, repr=True, eq=True, eq_key=None, order=True, order_key=None, hash=None, init=True, metadata=mappingproxy({}), type='None | str', converter=None, kw_only=True, inherited=False, on_setattr=None, alias='envdir'), <class 'str'>, PosixPath('.venv'))
Error: Process completed with exit code 1.
```

### Expected Behavior

Accept `nox.options.envdir = Path(".venv")`

### Steps To Reproduce

_No response_

### Environment

```Markdown
- OS: Ubuntu 22.04
- Python: 3.12
- Nox: 2025.02.09
```

### Anything else?

_No response_
