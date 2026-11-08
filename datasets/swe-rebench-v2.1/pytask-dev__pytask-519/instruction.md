BUG: can't use builtin functions due to inspect.py
- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest version of pytask.

- [ ] (optional) I have confirmed this bug exists on the `main` branch of pytask.

---

#### Code Sample, a copy-pastable example

```python
from pathlib import Path
import time

import pytask

task_build_time = pytask.task(produces=Path("build_time.txt"))(time.asctime)
```

```
╭─────────────────────────────── Traceback (most recent call last) ────────────────────────────────╮
│ in exec_module:940                                                                               │
│ in _call_with_frames_removed:241                                                                 │
│                                                                                                  │
│ /Users/nc/code/scg/kobuk/kobuk/tasks2/task_bug.py:6 in <module>                                  │
│                                                                                                  │
│   3                                                                                              │
│   4 import pytask                                                                                │
│   5                                                                                              │
│ ❱ 6 task_build_time = pytask.task(produces=Path("build_time.txt"))(time.asctime)                    │
│   7                                                                                              │
│                                                                                                  │
│ /Users/nc/code/scg/kobuk/.venv/lib/python3.11/site-packages/_pytask/task_utils.py:97 in wrapper  │
│                                                                                                  │
│    94 │   │                                                                                      │
│    95 │   │   unwrapped = inspect.unwrap(func)                                                   │
│    96 │   │                                                                                      │
│ ❱  97 │   │   raw_path = inspect.getfile(unwrapped)                                              │
│    98 │   │   if "<string>" in raw_path:                                                         │
│    99 │   │   │   path = Path(unwrapped.__globals__["__file__"]).absolute().resolve()            │
│   100 │   │   else:                                                                              │
│                                                                                                  │
│ /Users/nc/.pyenv/versions/3.11.6/lib/python3.11/inspect.py:920 in getfile                        │
│                                                                                                  │
│    917 │   │   object = object.f_code                                                            │
│    918 │   if iscode(object):                                                                    │
│    919 │   │   return object.co_filename                                                         │
│ ❱  920 │   raise TypeError('module, class, method, function, traceback, frame, or '              │
│    921 │   │   │   │   │   'code object was expected, got {}'.format(                            │
│    922 │   │   │   │   │   type(object).__name__))                                               │
│    923                                                                                           │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
TypeError: module, class, method, function, traceback, frame, or code object was expected, got builtin_function_or_method
```

#### Problem description

#### Expected Output

Any callable should work?

### Additional contract requirements

Although the report asks whether "any callable should work?", the required resolution is
that built-in functions are **not** accepted as tasks. When the supplied callable is a
built-in function (an instance of ``types.BuiltinFunctionType``), ``pytask.task`` must
raise ``NotImplementedError`` with the message:

```
Builtin functions cannot be wrapped with '@task'. If necessary, wrap the builtin function in a function or lambda expression.
```

Regular Python functions and other non-builtin callables continue to work as tasks.
