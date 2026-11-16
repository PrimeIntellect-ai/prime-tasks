Configure models through class kwargs
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this feature/change is needed
* [x] After submitting this, I commit to one of:
    * Look through open issues and helped at least one other person
    * Hit the "watch" button on this repo to receive notifications and I commit to help at least 2 people that ask questions in the future
    * Implement a Pull Request for a confirmed bug
Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```py
             pydantic version: 1.6.1
            pydantic compiled: True
                 install path: /Users/rocky/.local/share/virtualenvs/superapp-search-hVQXXu_u/lib/python3.8/site-packages/pydantic
               python version: 3.8.7 (v3.8.7:6503f05dd5, Dec 21 2020, 12:45:15)  [Clang 6.0 (clang-600.0.57)]
                     platform: macOS-10.16-x86_64-i386-64bit
     optional deps. installed: ['typing-extensions']
```
# Feature Request
Allow to configure models through class kwargs, allowing more elegant and compact code

```py
from pydantic import BaseModel

class Model(BaseModel, alias_generator=str.upper):
    foo: int
    bar: int
```
==
```py
class Model(BaseModel)
    foo: int
    bar: int

    class Config:
        alias_generator = str.upper
```

Will be happy to implement this myself, once feature request is accepted.
