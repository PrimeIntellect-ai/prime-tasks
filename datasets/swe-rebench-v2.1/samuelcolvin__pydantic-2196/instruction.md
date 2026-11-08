Introduce a allow_mutation Field constraint
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this feature/change is needed
* [x] After submitting this, I commit to one of:
    * Look through open issues and helped at least one other person
    * Hit the "watch" button on this repo to receive notifications and I commit to help at least 2 people that ask questions in the future
    * Implement a Pull Request for a confirmed bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Feature Request
I found mentions of a readOnly parameter on the deprecated Schema class but it was not carried over to Field.  Others are using validators to enforce readonly on assignment, but it's a common enough feature that pydantic could provide it natively.  I am not able to use validators to create a readonly Field because I have validators that need to be run on initialization.

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.2
            pydantic compiled: False
                 install path: /Users/scootna/projects/pydantic/pydantic
               python version: 3.8.2 (default, Sep 24 2020, 19:37:08)  [Clang 12.0.0 (clang-1200.0.32.21)]
                     platform: macOS-10.15.7-x86_64-i386-64bit
     optional deps. installed: ['typing-extensions', 'email-validator', 'devtools']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your feature hasn't been asked for before, or already implemented. -->

<!-- Where possible please include a self-contained code snippet describing your feature request: -->

```py
from pydantic import BaseModel, Field

class Entry(BaseModel):
    id: float = Field(allow_mutation=False)
    val: float

    class Config:
        validate_assignment = True

r = Entry(id=1, val=100)
r.id = 2 # raise error when assigning to read_only field

...
```

### Additional contract requirements

- The public class `pydantic.fields.FieldInfo` accepts an `allow_mutation` keyword argument (default `True`) and exposes the supplied value as its `allow_mutation` attribute.
- Assigning to a field declared with `Field(allow_mutation=False)` on a model whose `Config.validate_assignment` is `True` raises a `TypeError` whose message is `"<field>" has allow_mutation set to False and cannot be assigned`, where `<field>` is the name of the field.
