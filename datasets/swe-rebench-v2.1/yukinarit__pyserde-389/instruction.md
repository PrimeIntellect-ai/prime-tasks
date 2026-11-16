from_yaml will return None with empty string
I assume this is a bug and not by design:

```py
from dataclasses import dataclass
from serde.yaml import from_yaml

@dataclass
class Foo:
  bar: str

good = '''
  bar: hello
'''

bad = '''
  no: hello
'''

from_yaml(Foo, good) # Foo(bar='hello') ✅
from_yaml(Foo, bad)  # raises SerdeError ✅
from_yaml(Foo, '')   # None 😱
```
