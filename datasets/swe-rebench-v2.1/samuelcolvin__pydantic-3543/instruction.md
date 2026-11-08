`Config.smart_union` doesn't work with `TypedDict`
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.9.0a1
            pydantic compiled: False
               python version: 3.10.0 (tags/v3.10.0:b494f59, Oct  4 2021, 19:00:18) [MSC v.1929 64 bit (AMD64)]
                     platform: Windows-10-10.0.22000-SP0
     optional deps. installed: ['typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

```py
class Dict1(TypedDict):
    foo: str


class Dict2(TypedDict):
    bar: str


class M(BaseModel):
    d: Union[Dict2, Dict1]

    class Config:
        smart_union = True


M(d=dict(foo='baz'))  # raises TypeError: isinstance() arg 2 must be a type, a tuple of types, or a union
```
