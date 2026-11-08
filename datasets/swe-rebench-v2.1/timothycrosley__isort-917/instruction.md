4.3.16 failing file check after isort
test.py

Before isort ->
```
#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals
```

After isort ->
```
#!/usr/bin/env python
# -*- coding: utf-8 -*-
# FUTURE
from __future__ import unicode_literals
```

isort -c test.py ->
```
ERROR: bla-bla-bla/test.py Imports are incorrectly sorted.
```

isort -df test.py ->
```
--- bla-bla-bla/test.py:before 2019-03-29 21:21:31.371673
+++ bla-bla-bla/test.py:after  2019-03-30 11:43:43.791501
@@ -1,4 +1,5 @@
 #!/usr/bin/env python
 # -*- coding: utf-8 -*-
 # FUTURE
+# FUTURE
 from __future__ import unicode_literals
```

Here's settings:
```
[settings]
known_future_library=future
import_heading_future=FUTURE
sections=FUTURE,STDLIB,NORDIGEN,FIRSTPARTY,THIRDPARTY,LOCALFOLDER
indent='    '
multi_line_output=3
lines_after_imports=2
```

Is this a bug or I'm doing something wrong and I can be changed thru settings?
Thanks.
