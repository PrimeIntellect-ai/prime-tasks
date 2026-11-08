`validate_assignment` changes the field order
### Checks

* [*] I added a descriptive title to this issue
* [*] I have searched (google, github) for similar issues and couldn't find anything
* [*] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

```
             pydantic version: 1.7.1
            pydantic compiled: True
                 install path: /home/user/work/bugs/python/pydantic-ordering/.venv/lib/python3.8/site-packages/pydantic
               python version: 3.8.5 (default, Jul 28 2020, 12:59:40)  [GCC 9.3.0]
                     platform: Linux-4.19.128-microsoft-standard-x86_64-with-glibc2.29
     optional deps. installed: []
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

Including `validate_assignment = True` in a model's config seems to cause assignment to change the field order when using `dict()`. This change was discovered when upgrading to 1.7.0 and also applies to 1.7.1, but was not present in prior versions.

This behaviour does not seem to agree with <https://pydantic-docs.helpmanual.io/usage/models/#field-ordering>, and is something that is important for my uses (where it generates massive diffs in the output) and surely others.

Running this snippet with and without the `validate_assignment` line produces different output:
```py
from pydantic import BaseModel

class Model(BaseModel):
    title: str = ''
    name: str = ''

    class Config:
        validate_assignment = True
        ...

m = Model(name='name')
m.title = 'title'
print(m.dict())
```

### Additional contract requirements

* With `validate_assignment` enabled, assigning a value to a model field must leave the order of the fields in `dict()` output unchanged.
