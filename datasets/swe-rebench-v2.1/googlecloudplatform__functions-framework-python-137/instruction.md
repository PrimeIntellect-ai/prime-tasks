Using decorator @functions_framework.errorhandler makes the python script impossible to import
Using decorator `@functions_framework.errorhandler` makes the python script impossible to import without creating an application.
Import produces the error:
```
AttributeError: module 'functions_framework' has no attribute 'errorhandler'
```

## Example
Trying to start run 'importer.py' script produce the above error.

decorated.py
```python
from typing import Tuple

from flask.typing import ResponseValue, StatusCode

import functions_framework


@functions_framework.errorhandler
def handle_exception(ex: Exception) -> Tuple[ResponseValue[str], StatusCode]:
    return "Unhandled exception", 500
```

importer.py
```python
import decorated

if __name__ == '__main__':
    print("Imported")

```

## Possible source of the issue

The error handler decorator is registered in [`functions_framework.create_app()`](https://github.com/GoogleCloudPlatform/functions-framework-python/blob/c7f66fd5ed9856bdf4e484774742d7c158ab7b43/src/functions_framework/__init__.py#L232) and it is not available without calling this functons.
