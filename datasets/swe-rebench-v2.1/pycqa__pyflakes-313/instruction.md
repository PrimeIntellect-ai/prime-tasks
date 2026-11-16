Typing.TYPE_CHECKING imports raise F401
```
$ pip install  flake8

```

```
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from my_module.test_class import MyClass

object: 'MyClass' = None
```
Flake 8 gives the following error in this scenario:

`my_module\test_class.py:4:5: F401 'my_module.test_class.MyClass' imported but unused`

My current work around is this:

```
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from my_module.test_class import MyClass  # noqa

object: 'MyClass' = None
```

Any better solutions? Couldwe somehow automatically ignore all F401 errors within the `if TYPE_CHECKING:` block?

### Additional contract requirements

- The first code sample above (the one that currently reports the F401 error) must not report an unused-import (F401) error.
- Add a public message class `ForwardAnnotationSyntaxError(filename, loc, annotation)` in `pyflakes/messages.py`. It formats the error as `syntax error in forward annotation '<annotation>'` and is reported when a string-based (forward) type annotation cannot be parsed.
