BUG: Inconsistent number of collected tasks when (sub)paths occur multiple times
- [x]  I have checked that this issue has not already been reported.
- [x] I have confirmed this bug exists on the latest version of pytask.
- [ ] (optional) I have confirmed this bug exists on the `main` branch of pytask.

---

When setting multiple pytask paths with common subdirectories, the tasks in those subdirectories are counted twice in the collection. I have checked, and they are not being executed twice. (This was originally discovered by @ChristianZimpelmann.)


#### Code Sample, a copy-pastable example

pytask version: 0.5.0

```console
$ cat pyproject.toml
```
```toml
[tool.pytask.ini_options]
paths = [
  ".",
  ".",
]
```

```console
$ cat task_a.py
```
```python
import random
from pathlib import Path

def task_a():
    Path(f"{random.randint(0, 10)}.txt").write_text("test")
```


#### Problem description

The first row says `Collected 2 tasks`, but in the Summary, it says `1 Collected tasks`.

![image](https://github.com/pytask-dev/pytask/assets/39708667/aff24335-8872-4e8f-a007-6b9db6b2960d)


#### Expected Output

I believe there should be the same number of collected tasks. Additionally, if the verbosity level is high, one could consider printing a warning.
