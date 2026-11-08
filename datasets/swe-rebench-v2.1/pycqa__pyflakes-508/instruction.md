F401 (imported but unused) false positive on Foo when using def x(a: Foo, /, *, b: Bar)
```python
from datetime import datetime as Foo, time as Bar


def x(a: Foo, /, *, b: Bar):
    pass
```

Running this on the file results in:

```
› flake8 --version
3.7.9 (mccabe: 0.6.1, pycodestyle: 2.5.0, pyflakes: 2.1.1) CPython 3.8.1 on Linux
› pyflakes --version
2.1.1 Python 3.8.1 on Linux
› flake8 example.py
example.py:1:1: F401 'datetime.datetime as Foo' imported but unused
› pyflakes example.py
example.py:1: 'datetime.datetime as Foo' imported but unused
```

### Additional contract requirements

Positional-only parameters (the parameters declared before `/` in a function signature) are ordinary function parameters: a reference to such a parameter inside the function body must not be reported as an undefined name.
