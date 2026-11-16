Spurious import warning for type used in nested quoted annotation
This is similar to #290 and #313, but seems to still be an issue.

If you import a type and then use it only within a type annotation which includes a nested quoted part, then `pyflakes` reports the import as unused.

``` python
from queue import Queue  # F401: 'queue.Queue' imported but unused
from typing import Optional

def foo(queue: Optional['Queue[int]'] = None) -> None:
    print(queue)

# Revealed type is 'def (queue: Union[queue.Queue[builtins.int], None] =)'
reveal_type(foo)
```

This can be worked around by quoting the whole of the type annotation:
``` python
def foo(queue: 'Optional[Queue[int]]' = None) -> None:
    print(queue)
```

I'm using pyflakes 2.1.1 on Python 3.5.2 on Linux.
