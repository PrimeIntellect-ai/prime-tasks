tidy-imports incorrectly removes import when used in decorator and matches with a parameter name (PyInf#11068)
tidy-imports incorrectly removes import when used in decorator and matches with a parameter name

```
import random

def repeat(times):
    def wrap(fn):
        def wrap_wrap(*args, **kwargs):
            for i in range(times):
                fn(*args, **kwargs)
        return wrap_wrap
    return wrap


@repeat(random.choice([1, 4]))
def foo(random):
    print(random)
```

```
$ tidy-imports repro.py
...
-import random
...
```
