MapAdapter.build() should not flatten a value passed as single-item-list
<!--
This issue tracker is a tool to address bugs in Werkzeug itself. Please
use Pallets Discord or Stack Overflow for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->
Let's consider this code:

```
from flask import Flask, url_for
import logging

app = Flask(__name__)

@app.route('/test/<int:x>')
def urltest(x):
    return f"{x}"

@app.route("/")
def main():
    BUILT_URL = url_for('urltest', x=[1337])
    logging.warning(BUILT_URL)
    return ""
```

since Werkzeug v2 (apparently since b45b508c48cfca5ccbb582fdc39bbf486bed4e1a), `BUILT_URL` obtains a value `/test/1337`. But, as I understand, the call should have raised an error, because the type of parameter `x` is obviously wrong and should be `int`, not `List[int]`. If the value is a list containing single item, it is transformed to just that item. If the value contains many items, it is passed to [converter](https://github.com/pallets/werkzeug/blob/fb7ddd89ae3072e4f4002701a643eb247a402b64/src/werkzeug/routing.py#L1189) as is.

This behavior breaks my application, because I use the custom converter for lists, similar to this one: https://uniwebsidad.com/libros/explore-flask/chapter-6/url-converters#custom-converters

I don't know, maybe it is a bad idea to build URLs from a list, but this behavior feels just wrong.


<!--
Describe how to replicate the bug.

Include a minimal reproducible example that demonstrates the bug.
Include the full traceback if there was an exception.
-->

<!--
Describe the expected behavior that should have happened but didn't.
-->

Environment:

- Python version: 3.8.5
- Werkzeug version: 2.0.1

### Additional contract requirements

- When a plain dict of values is passed to `MapAdapter.build`, a list value is handed to the URL converter as a list, even when it contains a single item. A single-item list must not be unwrapped to its item.
- When a plain dict of values is passed to `MapAdapter.build`, `None` entries inside a list value are kept and passed to the converter; they are not filtered out.
- Passing a single-item list for an integer path parameter must not succeed by silently unwrapping it; building the URL must fail with a conversion error (`TypeError`, `ValueError` or `BuildError`).
