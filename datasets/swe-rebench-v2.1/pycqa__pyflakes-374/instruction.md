F821 Error with Forward Reference and `from __future__ import annotations`
With this example file:

```python
# test.py
from __future__ import annotations
from dataclasses import dataclass

@dataclass
class MyData:
    member: MyMember

@dataclass
class MyMember:
    value: int
```

I get an F821 error:
```shell
$ flake8 --select=F test.py
test.py:8:13: F821 undefined name 'MyMember'
```

I suppose the error is correct, but forward references in this form are explicitly supported with the `annotations` future and I think this should be changed in some manner.
