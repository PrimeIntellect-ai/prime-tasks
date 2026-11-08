"none is not an allowed value" when using Union with Any
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

# Bug
It seems that `None` is allowed when a field's type is `Any` (as is expected, stated in the docs), but `None` is not allowed when a field's type is `Union[SomeType, Any]`.

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.8.2
            pydantic compiled: True
                 install path: C:\Users\TobyHarradine\PycharmProjects\orchestration\.venv\Lib\site-packages\pydantic
               python version: 3.7.9 (tags/v3.7.9:13c94747c7, Aug 17 2020, 18:58:18) [MSC v.1900 64 bit (AMD64)]
                     platform: Windows-10-10.0.19041-SP0
     optional deps. installed: ['typing-extensions']
```

Code which reproduces the issue:
```pycon
>>> import pydantic
>>> class M(pydantic.BaseModel):
...     a: Any
...
>>> M(a=1)
M(a=1)
>>> M(a=None)
M(a=None)
>>> class M(pydantic.BaseModel):
...     a: Union[int, Any]
...
>>> M(a=1)
M(a=1)
>>> M(a="abcd")
M(a='abcd')
>>> M(a=None)
Traceback (most recent call last):
  File "<input>", line 1, in <module>
  File "pydantic\main.py", line 406, in pydantic.main.BaseModel.__init__
pydantic.error_wrappers.ValidationError: 1 validation error for M
a
  none is not an allowed value (type=type_error.none.not_allowed)

```

This may be somewhat related to #1624.
