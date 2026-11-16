Literal types produce incorrect docstring
**Describe the bug**
Argument which type is defined with typing.Literal produces incorrect docstring.

**Versions (please complete the following information):**
- autoDocstring Version: v0.5.4
- Operating System: macOS 12.0.1
- Vscode Version: 1.63.2

**Original Code (with line to generate on):**
```python
from typing import Literal

def foo(bar: Literal["baz"]) -> None:
# generate on this line
    pass
```

**Expected Result:**
```python
from typing import Literal


def foo(bar: Literal["baz"]) -> None:
    """[summary]

    Args:
        bar (Literal["baz"]): [description]
    """
    pass
```

**Actual Result:**
```python
from typing import Literal


def foo(bar: Literal["baz"]) -> None:
    """[summary]

    Args:
        bar (Literal[): [description]
    """
    pass
```
