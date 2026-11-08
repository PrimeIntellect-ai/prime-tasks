Failure on imports on one line wrapped in parantheses
```py
from foo import (bar, baz)
```

```
Error sorting main.py: Expected a ParenthesizedWhitespace but got a SimpleWhitespace!
```

### Additional contract requirements

- When sorting `from delta import echo, foxtrot` and `from alfa import (bravo, charlie)  # hello`, the output must be:
```py
from alfa import bravo, charlie  # hello
from delta import echo, foxtrot
```
