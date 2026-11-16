_ReprClass instances are treated as constants, so 'is' and 'is not' comparisons to them shouldn't break after a deepcopy.
### Description

We have many 'is' and 'is not' comparisons to various _ReprClass objects like _UNDEFINED and _DEFAULT_OUT_STREAM which we treat as constants.  If we deepcopy an object that contains a _ReprClass object, those 'is' and 'is not' comparisons will break in the copy.

### Example

```python
import copy
from openmdao.core.constants import _UNDEFINED

class Foo(object):
    def __init__(self):
        self.bar = _UNDEFINED

f = Foo()
cpf = copy.deepcopy(f)

assert cpf.bar is _UNDEFINED, "Constants don't match!"
```


### OpenMDAO Version

3.21.1-dev

### Relevant environment information

_No response_
