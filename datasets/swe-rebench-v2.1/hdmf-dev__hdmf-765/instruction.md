[Bug]: get_hdf5io() does not work
### What happened?

A recent refactoring of `get_hdf5io` broke the code so now it raises an error on correct usage. There are no unit tests for this function.

### Steps to Reproduce

```shell
with get_hdf5io(self.path, "w") as io:
   pass
```


### Traceback

```shell
self = <tests.unit.common.test_common_io.TestGetHdf5IO testMethod=test_gethdf5io>

    def test_gethdf5io(self):
        """Test the get_hdf5io convenience method with manager=None."""
>       with get_hdf5io(self.path, "w") as io:

tests/unit/common/test_common_io.py:82:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
src/hdmf/utils.py:649: in func_call
    return func(**pargs)
src/hdmf/common/__init__.py:189: in get_hdf5io
    [HIDDEN]
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

args = ()
kwargs = {'comm': None, 'driver': None, 'file': None, 'manager': <hdmf.build.manager.BuildManager object at 0x12f681d30>, ...}
pargs = {'comm': None, 'driver': None, 'file': None, 'manager': <hdmf.build.manager.BuildManager object at 0x12f681d30>, ...}

    def func_call(*args, **kwargs):
        pargs = _check_args(args, kwargs)
>       return func(args[0], **pargs)
E       IndexError: tuple index out of range

src/hdmf/utils.py:645: IndexError
```


### Operating System

macOS

### Python Executable

Python

### Python Version

3.9

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/hdmf-dev/hdmf/blob/dev/.github/CODE_OF_CONDUCT.md)
- [X] Have you checked the [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/hdmf-dev/hdmf/issues)?

### Additional contract requirements

- Calling `get_hdf5io` with a file path and mode and no supplied manager must return an object that can be used in a `with` statement without raising.
