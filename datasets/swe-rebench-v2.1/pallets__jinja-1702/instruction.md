TypeError: sequence item 0: expected str instance, int found
```python
import jinja2
from jinja2.nativetypes import NativeEnvironment
NativeEnvironment().from_string('{% block test %}{% for i in range(1) %}{{ loop.index }}{% endfor %}{% endblock %}{{ self.test() }}').render()
```

```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/phemmer/.local/lib/python3.10/site-packages/jinja2/nativetypes.py", line 112, in render
    return self.environment.handle_exception()
  File "/home/phemmer/.local/lib/python3.10/site-packages/jinja2/environment.py", line 936, in handle_exception
    raise rewrite_traceback_stack(source=source)
  File "/home/phemmer/.local/lib/python3.10/site-packages/jinja2/nativetypes.py", line 25, in native_concat
    head = list(islice(values, 2))
  File "<template>", line 1, in top-level template code
TypeError: sequence item 0: expected str instance, int found
```

Environment:

- Python version: Python 3.10.5

- Jinja version: 3.1.2
