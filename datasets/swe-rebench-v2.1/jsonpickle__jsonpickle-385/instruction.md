Private members of __slots__ are skipped
Issue
-------------

"private" members of `__slots__` are skipped, but not private members of `__dict__`.

Steps to reproduce
--------------------------

In the following code, the two classes are identical apart from that the first uses `__slots__` and the second uses `__dict__`.

### Actual result
 `jsonpickle` ignores the private `__beta` member in the `__slots__` version, but not in the `__dict__` version.

### Expected result
Similar behaviour for both classes.

### Code

```
class MySlots:
    __slots__ = "alpha", "__beta"

    def __init__( self ):
        self.alpha = 1
        self.__beta = 2

class MyDict:
    def __init__( self ):
        self.alpha = 1
        self.__beta = 2

def print_obj( obj ):
    alpha = getattr( obj, "alpha", "(missing)" )
    beta = getattr( obj, f"_{obj.__class__.__name__}__beta", "(missing)" )
    print( f"{alpha=}, {beta=}" )

import jsonpickle

slots_orig = MySlots()
dict_orig = MyDict()

print_obj( slots_orig ) # alpha=1, beta=2
print_obj( dict_orig ) # alpha=1, beta=2

slots_str = jsonpickle.dumps( slots_orig )
dict_str = jsonpickle.dumps( dict_orig )

slots_recon = jsonpickle.loads( slots_str )
dict_recon = jsonpickle.loads( dict_str )

print_obj( slots_recon ) # alpha=1, beta='(missing)'
print_obj( dict_recon ) # alpha=1, beta=2
```

Jsonpickle 1.3, Python 3.8.2, Windows 10.
