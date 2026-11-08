syntax error in forward annotation when using Annotated
When using [`Annotated`](https://www.python.org/dev/peps/pep-0593/) with string annotations the following error is raised:

```
./pyflakes.py:3:16 syntax error in forward annotation '>1'
```

Triggering code:

```
from typing import Annotated

Annotated[int, '>1']
```
