validate_assignment with side effect validators
# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.2
            pydantic compiled: True
                 install path: /home/arthur/Documents/odmantic/.venv/lib/python3.8/site-packages/pydantic
               python version: 3.8.1 (default, Jan  5 2020, 23:12:00)  [GCC 7.3.0]
                     platform: Linux-4.17.14-041714-generic-x86_64-with-glibc2.27
     optional deps. installed: ['typing-extensions']
```

```py
from pydantic import root_validator, BaseModel

class Rectangle(BaseModel):
    width: float
    height: float
    area: float = None

    class Config:
        validate_assignment = True

    @root_validator()
    def set_ts_now(cls, v):
        v["area"] = v["width"] * v["height"]
        return v

r = Rectangle(width=1, height=1)
assert r.area == 1
r.height = 5
assert r.area == 5 # AssertionError, r.area has not been modified
```
I don't know if it should be allowed to use validators this way or if it's a real bug.
I'd be happy to try to implement a fix :smile:

### Additional contract requirements

- When `validate_assignment` is enabled and a `root_validator` modifies fields other than the one being assigned, every modified field value must be reflected on the model after the assignment, so that reading those fields returns the values the root validator produced.
