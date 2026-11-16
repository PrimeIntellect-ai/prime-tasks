isort is non-deterministic with multiple forced_separate groups
`forced_separate` groups that are specified in a config file can result in non-deterministic sorting. For example:

The following configuration in a setup.cfg, tox.ini etc

```
[isort]
forced_separate:
    separate1
    separate2
```

Should result in:

```
import time

from separate1 import foo

from separate2 import bar
```

But [HIDDEN], sometimes the order is switched to:

```
import time

from separate2 import bar

from separate1 import foo
```

### Additional contract requirements

- When imports belong to multiple `forced_separate` groups, the groups must appear in the order they are listed in the configuration.
- Repeated sorting of the same input with the same configuration must preserve that order.
