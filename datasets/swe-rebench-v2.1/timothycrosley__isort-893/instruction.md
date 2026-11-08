Might create blank line at start of file with comments
Running `isort --diff` with the following will add a blank line at the start:
```python
# comment
import os
# comment2
import sys
```

```diff
@@ -1,4 +1,5 @@
+
+import os
 # comment
-import os
 # comment2
 import sys
```

The result then looks like this:
```python

import os
# comment
# comment2
import sys
```
