underscore_attrs_are_private causes TypeError
### Checks

- [x] I added a descriptive title to this issue
- [x] I have searched (google, github) for similar issues and couldn't find anything
- [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:

```
        pydantic version: 1.7
       pydantic compiled: True
            install path: /Users/ahedges/.pyenv/versions/3.7.8/envs/sdf/lib/python3.7/site-packages/pydantic
          python version: 3.7.8 (default, Sep 16 2020, 18:33:23)  [Clang 11.0.3 (clang-1103.0.32.59)]
                platform: Darwin-19.6.0-x86_64-i386-64bit
optional deps. installed: ['typing-extensions']
```

I spent a decent amount of time this weekend trying to make a private field using code posted in #655. I was happy to see Pydantic 1.7 came out today and had support for private fields built in. I upgraded and tried to convert my code, but I encountered some unusual problems. (Even though it doesn't work perfectly, I still appreciate the feature.) Most are type errors from mypy (might report later), but this one is more serious. I simplified the problem below.

The issue is that `underscore_attrs_are_private` causes an exception where `PrivateAttr` does not.

When using `underscore_attrs_are_private` with the following code:

```python
from typing import Any
from pydantic import BaseModel

class TestObject(BaseModel):
    public_field: str
    _private_field: str

    class Config:
        underscore_attrs_are_private = True

    def __init__(self, **data: Any) -> None:
        super().__init__(**data)
        self._private_field = "bar"

print(TestObject(public_field="foo"))
```

I get the following output:

```
test.py:4: DeprecationWarning: __class__ not set defining 'TestObject' as <class '__main__.TestObject'>. Was __classcell__ propagated to type.__new__?
  class TestObject(BaseModel):
Traceback (most recent call last):
  File "test.py", line 15, in <module>
    print(TestObject(public_field="foo"))
  File "test.py", line 12, in __init__
    super().__init__(**data)
  File "pydantic/main.py", line 365, in pydantic.main.BaseModel.__init__
  File "pydantic/main.py", line 424, in pydantic.main.BaseModel._init_private_attributes
  File "pydantic/fields.py", line 821, in pydantic.fields.PrivateAttr.get_default
  File "pydantic/utils.py", line 624, in pydantic.utils.smart_deepcopy
  File "/Users/ahedges/.pyenv/versions/3.7.8/lib/python3.7/copy.py", line 169, in deepcopy
    rv = reductor(4)
TypeError: can't pickle cell objects
```

However, when using `PrivateAttr` with the following code:

```python
from typing import Any
from pydantic import BaseModel, PrivateAttr

class TestObject(BaseModel):
    public_field: str
    _private_field: str = PrivateAttr()

    def __init__(self, **data: Any) -> None:
        super().__init__(**data)
        self._private_field = "bar"

print(TestObject(public_field="foo"))
```

I get the following, desired output:

```
public_field='foo'
```

I also noticed that removing `__init__()` from the first example also prevents the crash. However, it is needed to set the private field.

Another thing to note is that in my full code, the exception caused by `underscore_attrs_are_private` appears but the `DeprecationWarning` does not. If you think this matters, I can try to reproduce my code without the warning.
