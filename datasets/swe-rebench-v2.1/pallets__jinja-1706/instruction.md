The error message from PackageLoader could be more helpful
When following [the basics of setting up jinja2](https://jinja.palletsprojects.com/en/3.1.x/api/#basics), if you don't create the appropriate `templates` directory in your package, you get this error message:

```
ValueError: The 'mypackage' package was not installed in a way that PackageLoader understands.
```

This could be significantly improved by explaining the actual problem: The PackageLoader could not find a suitable "templates" directory.

To replicate, add this to `mypackage.py`:

```python
from jinja2 import Environment, PackageLoader


env = Environment(loader=PackageLoader("mypackage"))
```

If you run `python mypackage.py` you will see a traceback similar to this:

```python
Traceback (most recent call last):
  File "mypackage/mypackage.py", line 4, in <module>
    env = Environment(loader=PackageLoader("mypackage"))
  File ".virtualenvs/mypackage/lib/python3.10/site-packages/jinja2/loaders.py", line 291, in __init__
    import_module(package_name)
  File ".pyenv/versions/3.10.3/lib/python3.10/importlib/__init__.py", line 126, in import_module
    return _bootstrap._gcd_import(name[level:], package, level)
  File "<frozen importlib._bootstrap>", line 1050, in _gcd_import
  File "<frozen importlib._bootstrap>", line 1027, in _find_and_load
  File "<frozen importlib._bootstrap>", line 1006, in _find_and_load_unlocked
  File "<frozen importlib._bootstrap>", line 688, in _load_unlocked
  File "<frozen importlib._bootstrap_external>", line 883, in exec_module
  File "<frozen importlib._bootstrap>", line 241, in _call_with_frames_removed
  File "mypackage/mypackage.py", line 4, in <module>
    env = Environment(loader=PackageLoader("mypackage"))
  File ".virtualenvs/mypackage/lib/python3.10/site-packages/jinja2/loaders.py", line 323, in __init__
    raise ValueError(
ValueError: The 'mypackage' package was not installed in a way that PackageLoader understands.

```

Seeing an error message that explained that jinja2 couldn't find an appropriate "templates" directory would be much better.

Environment:

- Python version: 3.10.3
- Jinja version: 3.1.2

### Additional contract requirements

- `PackageLoader` is constructed as `PackageLoader(package_name, package_path="templates", encoding="utf-8")`, where `package_path` is the relative path inside the package that contains the templates.
- When the package does not contain a directory matching `package_path`, constructing the loader raises `ValueError`. The error message includes the phrase `could not find a '<package_path>' directory`, using the supplied `package_path` value (for example, `could not find a 'templates' directory` for the default path).
