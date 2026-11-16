HTTPException.description can no longer be None in werkzeug 2.x.
<!--
This issue tracker is a tool to address bugs in Werkzeug itself. Please
use Pallets Discord or Stack Overflow for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->

The werkzeug HTTPException class has a `description` property, which is allowed to be `None` according to type hints.

In werkzeug 1.x, this worked fine. In werkzeug 2.x, having `description` set to None leads to an exception:

```python
Python 3.7.5 (v3.7.5:5c02a39a0b, Oct 14 2019, 18:49:57)
[Clang 6.0 (clang-600.0.57)] on darwin
from werkzeug.exceptions import HTTPException
e = HTTPException()
e.get_description()
Traceback (most recent call last):
  File "<input>", line 1, in <module>
  File "/Users/d073668/work/ml/meh/ML-MEH-Commons/venv/lib/python3.7/site-packages/werkzeug/exceptions.py", line 158, in get_description
    description = escape(self.description).replace("\n", "<br>")  # type: ignore
  File "/Library/Frameworks/Python.framework/Versions/3.7/lib/python3.7/html/__init__.py", line 19, in escape
    s = s.replace("&", "&amp;") # Must be done first!
AttributeError: 'NoneType' object has no attribute 'replace'
```

I believe this error is happening because the `escape` function used in `HTTPException.get_description` has been replaced. In Werkzeug 1.x, this was `werkzeug.utils.escape` which replaces `None` with the empty string`""`. In werkzeug 2.x, this is now coming from Python's built-in `html` package, which does not handle `None`.

Environment:

- Python version: 3.7.5
- Werkzeug version: 2.0.0 (broken)
