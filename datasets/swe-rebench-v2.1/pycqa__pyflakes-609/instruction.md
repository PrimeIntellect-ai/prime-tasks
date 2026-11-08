Nested TypedDict not supported
Flake8 returns strange `undefined name` errors when using nested [alternative syntax style](https://www.python.org/dev/peps/pep-0589/#alternative-syntax) `TypedDict` declarations.

Example:

```py
from typing import TypedDict


class Example(TypedDict):
    nested: TypedDict("Nested", {"foo/bar": str})
```

Pyflakes returns the following:
```sh
foo.py:5:23 undefined name 'Nested'
foo.py:5:34 undefined name 'foo'
foo.py:5:34 undefined name 'bar'
```

Version information:
```sh
$ pyflakes --version
2.2.0 Python 3.8.0 on Darwin
```


A workaround is to simply not nest the declarations:

```py
from typing import TypedDict


Nested = TypedDict("Nested", {"foo/bar": str})


class Example(TypedDict):
    nested: Nested
```
