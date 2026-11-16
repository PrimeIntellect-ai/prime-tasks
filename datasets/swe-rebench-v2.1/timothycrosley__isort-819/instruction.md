isort removes comments between imports
If the following code is processed with isort the comment is removed.

```python
import distutils
# this comment is important and should not be removed
from sys import api_version as api_version
```

This was reported in https://github.com/coala/coala-bears/issues/1929 as we use isort through coala.

I'm not even sure what the intended behavior is here, since sorting imports with comments could raise all kinds of problems, but removing them seems wrong too.

Have you thought about this problem yet?
