DeprecationWarning: the imp module is deprecated in favour of importlib
Modules such as scikit-learn that use cloudpickle and do not filer DeprecationWarning get the following when importing cloudpickle.

```
DeprecationWarning: the imp module is deprecated in favour of importlib; see the module's documentation for alternative uses import imp
```

Another way to display this is to launch python with the `-Wd` flag:

```
$ python -Wd -c "import cloudpickle"
/path/to/cloudpickle/cloudpickle.py:47: DeprecationWarning: the imp module is deprecated in favour of importlib; see the module's documentation for alternative uses
  import imp
```

We should therefore refactor cloudpickle to use importlib instead of imp while taking care of not breaking backward compat.

We should also run the tests of cloudpickle in a way that they would fail in case of uncaught deprecation warnings.

### Additional contract requirements

- Provide a function `_is_dynamic(module)` in the `cloudpickle.cloudpickle`
  module. It takes a module object and returns a boolean: `True` when the
  module was created dynamically (for example via `types.ModuleType`) and
  therefore cannot be imported by its name, and `False` for modules that can be
  imported normally, including standard library modules, packages and
  submodules of packages.
