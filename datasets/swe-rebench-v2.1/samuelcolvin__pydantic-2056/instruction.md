Pattern type serialisation error
### Checks

* [X] I added a descriptive title to this issue
* [X] I have searched (google, github) for similar issues and couldn't find anything
* [X] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7
            pydantic compiled: True
                 install path: /root/.local/lib/python3.8/site-packages/pydantic
               python version: 3.8.6 (default, Oct 13 2020, 20:49:19)  [GCC 8.3.0]
                     platform: Linux-3.10.0-1127.19.1.el7.x86_64-x86_64-with-glibc2.2.5
     optional deps. installed: ['email-validator']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

```py
from typing import Pattern
from pydantic import BaseModel

class Model(BaseModel):
    filter: Pattern

Model(filter="^regex$").json()
```

This produce an error :
TypeError: Object of type 'Pattern' is not JSON serializable

I had to write a custom encoder to be able to serialize properly a Pattern type :

```py
from typing import Pattern
from pydantic import BaseModel
import re

class Model(BaseModel):
    filter: Pattern
    class Config:
        json_encoders = {
            re.Pattern: lambda v: v.pattern,
        }

Model(filter="^regex$").json()
```
