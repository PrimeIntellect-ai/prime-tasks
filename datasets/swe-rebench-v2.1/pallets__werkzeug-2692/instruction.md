Use of warnings.catch_warnings resets the global warnings registry
There is a long-standing bug in Python python/cpython#73858 whereby any use of `warnings.catch_warnings` causes all memory of which warnings have already been displayed to be lost.  So warnings whose [action](https://docs.python.org/3/library/warnings.html#the-warnings-filter) is configured as "default" (meaning show once for each module/line-number) get displayed multiple (possibly many, many) times.

Note that use of `catch_warnings` resets memory of what warnings have been displayed globally — use of `catch_warnings` by werkzeug can cause redisplay of unrelated warnings from other modules.

PR #2608 (19d55c1e01d628d9a256526b573f478248d4bc5a) introduced a lot of new uses of `catch_warnings`.

I'm not sure what the clean way is to work-around the issue, but it would be nice not to break the "default" warning action so drastically.

<!--
This issue tracker is a tool to address bugs in Werkzeug itself. Please
use Pallets Discord or Stack Overflow for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->

<!--
Describe how to replicate the bug.

Include a minimal reproducible example that demonstrates the bug.
Include the full traceback if there was an exception.
-->
Example: `too-verbose.py`:
```py
from werkzeug.urls import url_parse

for _ in range(10):
    url_parse("x")
```

Running
```sh
python too-verbose.py
```
will elicit 10 `url_parse` deprecation warnings.  (The default warnings filter specifies an action of "default" for DeprecationWarnings, which means that they should be displayed just once per location.)

<!--
Describe the expected behavior that should have happened but didn't.
-->

Environment:

- Python version: I've tested under 3.9 and 3.11.  I think it affects all 3.x pythons.
- Werkzeug version: 2.3.3
