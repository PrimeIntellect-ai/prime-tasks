typing.Counter is not supported
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7
            pydantic compiled: True
                 install path: /home/user/app/.venv/lib/python3.8/site-packages/pydantic
               python version: 3.8.6 (default, Sep 25 2020, 09:36:53)  [GCC 10.2.0]
                     platform: Linux-5.9.0-1-amd64-x86_64-with-glibc2.29
     optional deps. installed: ['typing-extensions']
```

Minimal example:

```python
from typing import Counter
from pydantic import BaseModel
class ProcessedDoc(BaseModel):
    named_entities: Counter[str]
```

Result:

```text
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "pydantic/main.py", line 262, in pydantic.main.ModelMetaclass.__new__
  File "pydantic/fields.py", line 315, in pydantic.fields.ModelField.infer
  File "pydantic/fields.py", line 284, in pydantic.fields.ModelField.__init__
  File "pydantic/fields.py", line 356, in pydantic.fields.ModelField.prepare
  File "pydantic/fields.py", line 492, in pydantic.fields.ModelField._type_analysis
IndexError: tuple index out of range
```

### Additional contract requirements

- A model field annotated `typing.Counter[T]` accepts a mapping of keys to integers and stores the value as a `collections.Counter`.
- For a field `x: Counter[T]`, `Model.__fields__['x'].type_` is `int`.
- A `Counter` field is displayed in the model representation as `Counter({...})`, for example `Model(x=Counter({'a': 10}))`.
- For `Model(x={'a': 'a'})` with `x: Counter[str]`, `ValidationError.errors()` returns `[{'loc': ('x', 'a'), 'msg': 'value is not a valid integer', 'type': 'type_error.integer'}]`.
