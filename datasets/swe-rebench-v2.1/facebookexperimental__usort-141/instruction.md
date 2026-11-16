Feature: split basic imports
```py
import os, sys, time
```
should be split into multiple import statements:
```py
import os
import sys
import time
```

### Additional contract requirements

- When splitting a basic import, repeat its preceding `# directive: foo` comment before each resulting import, and retain its inline `# noqa` comment on each resulting import. If a resulting import is merged with one carrying `# fun`, preserve both inline comments as `import math  # noqa  # fun`.
