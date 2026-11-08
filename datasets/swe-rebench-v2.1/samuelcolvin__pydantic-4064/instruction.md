Self-referenced ClassVar causes TypeError: issubclass() arg 1 must be a class (in 1.9.0, worked in 1.8.2)
### Checks

* [X] I added a descriptive title to this issue
* [X] I have searched (google, github) for similar issues and couldn't find anything -> Issue #545 is similar, but this case is a regression in 1.9.
* [X] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
pydantic version: 1.9.0
pydantic compiled: True
install path: C:\Program Files\Python39\Lib\site-packages\pydantic
python version: 3.9.0 (tags/v3.9.0:9cf6752, Oct  5 2020, 15:34:40) [MSC v.1927 64 bit (AMD64)]
platform: Windows-10-10.0.19041-SP0
optional deps. installed: ['email-validator', 'typing-extensions']
```
Also occurs on Linux with Python 3.9.9.


```py
from __future__ import annotations
import pydantic
import typing

class WithClassVar(pydantic.BaseModel):
    Instances : typing.ClassVar[dict[str,WithClassVar]] = {} # fails with issubclass() arg 1 must be a class; arg  1 is typing.ClassVar object
    # Instances : typing.ClassVar[dict[str,'WithClassVar']] = {} # works
    # instance : dict[str,WithClassVar] = {} # no classvar - works

...
```
I believe this case is specific to a ClassVar referencing itself. The argument passed to `issubclass `is not a class, but an instance of `typing.ClassVar`.

Call stack:

```
__subclasscheck__ (c:\Program Files\Python39\Lib\typing.py:789)
pydantic.fields.ModelField._type_analysis (c:\Program Files\Python39\Lib\site-packages\pydantic\fields.py:638)
pydantic.fields.ModelField.prepare (c:\Program Files\Python39\Lib\site-packages\pydantic\fields.py:534)
pydantic.typing.update_field_forward_refs (c:\Program Files\Python39\Lib\site-packages\pydantic\typing.py:451)
pydantic.typing.update_model_forward_refs (c:\Program Files\Python39\Lib\site-packages\pydantic\typing.py:480)
pydantic.main.BaseModel.__try_update_forward_refs__ (c:\Program Files\Python39\Lib\site-packages\pydantic\main.py:773)
pydantic.main.ModelMetaclass.__new__ (c:\Program Files\Python39\Lib\site-packages\pydantic\main.py:292)
<module> (.... \pydantic_bug.py:5)
```
