Sort completions so that the one most resembling the typing code comes first
With this example code:

```py
from logbook import Logger


logger = Logger(__name)
```

Every time I type: `logg`, Jedi will return

```
Logger
logger
```

whereas I expect:

```
logger
Logger
```
