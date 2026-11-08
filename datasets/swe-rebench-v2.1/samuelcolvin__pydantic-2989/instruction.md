Using PrivateAttr with multiple inheritance does not work because of the use of __slots__
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Using PrivateAttr with multiple inheritance does not work because of the use of `__slots__`. [HIDDEN]

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.8.2
            pydantic compiled: False
                 install path: /home/HOME/git/pydantic/pydantic
               python version: 3.8.10 (default, Jun  2 2021, 10:49:15)  [GCC 9.4.0]
                     platform: Linux-5.4.0-77-generic-x86_64-with-glibc2.29
     optional deps. installed: ['devtools', 'dotenv', 'email-validator', 'typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

```py
from pydantic import BaseModel

default = {'a': {}}

class GrandParentModel(BaseModel):
    __foo__ = PrivateAttr(default)

class ParentAModel(GrandParentModel):
    pass

class ParentBModel(GrandParentModel):
    __bar__ = PrivateAttr(default)

class Model(ParentAModel, ParentBModel):
    __baz__ = PrivateAttr(default)
```
gives: TypeError: multiple bases have instance lay-out conflict

### Additional contract requirements

- A `BaseModel` subclass combining multiple inheritance branches that use `PrivateAttr` must be definable without an instance-layout conflict.
- Private attributes declared on a common ancestor, an inheritance branch, or the resulting child must remain accessible and assignable on instances of the combined child.
