Required optional field has a default value of None after v1.7.0
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.2
            pydantic compiled: False
                 install path: /home/leovp/Projects/pydantic/pydantic
               python version: 3.6.12 (default, Sep  5 2020, 11:22:16)  [GCC 7.5.0]
                     platform: Linux-4.15.0-54-generic-x86_64-with-debian-buster-sid
     optional deps. installed: []
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

```py
from typing import Optional

from pydantic import BaseModel


class Model(BaseModel):
    foo: int
    bar: Optional[int] = ...


m = Model(foo=1, bar=None)  # or Model(foo=1)
Model.parse_obj(m.dict(exclude_defaults=True))  # fails on pydantic v1.7.0+
```

It seems that `pydantic` thinks `bar` (a "required optional" field) has a default value of None and serializes the model without this key, which makes it non-deserializable. This was not the case on versions 1.5.x and 1.6.x, so I think it's a regression. (Or maybe it was never a guarantee).

According to `git bisect` the potential regression was introduced in commit 4bc4230df6294c62667fc3779328019a28912147.
