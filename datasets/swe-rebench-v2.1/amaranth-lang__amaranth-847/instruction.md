`Layout.const` doesn't properly mask signed values
```
from amaranth.lib import data
from amaranth import *

class Abc(data.Struct):
    a: signed(8)
    b: signed(8)
    c: signed(8)

print(hex(Abc.const({
    'a': 1,
    'c': 1,
    'b': -1,
}).value))

print(hex(Abc.const({
    'a': 1,
    'b': -1,
    'c': 1,
}).value))
```

Result:

```
0xffff01
0x1ff01
```
