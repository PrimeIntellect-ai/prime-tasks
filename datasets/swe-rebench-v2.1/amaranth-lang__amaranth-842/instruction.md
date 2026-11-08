TypeError when using Const as reset value of a Signal with a lib.data.Layout
Repro:
```python3
from amaranth import *
from amaranth.lib import data

layout = data.StructLayout({"foo": unsigned(1)})
s = Signal(layout, reset={"foo": Const(0)})
```

Output:
```
Traceback (most recent call last):
  File "/home/jf/src/amaranth/amaranth/hdl/ast.py", line 1040, in __init__
    reset = Const.cast(orig_shape.const(reset))
                       ^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/jf/src/amaranth/amaranth/lib/data.py", line 242, in const
    [HIDDEN]
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/jf/src/amaranth/amaranth/hdl/ast.py", line 659, in __init__
    self.value = int(value)
                 ^^^^^^^^^^
TypeError: int() argument must be a string, a bytes-like object or a real number, not 'Const'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/tmp/repro.py", line 5, in <module>
    s = Signal(layout, reset={"foo": Const(0)})
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/jf/src/amaranth/amaranth/hdl/ast.py", line 973, in __call__
    signal = super().__call__(shape, **kwargs, src_loc_at=src_loc_at + 1)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/jf/src/amaranth/amaranth/hdl/ast.py", line 1042, in __init__
    raise TypeError("Reset value must be a constant initializer of {!r}"
TypeError: Reset value must be a constant initializer of StructLayout({'foo': unsigned(1)})
```

### Additional contract requirements

- A `Signal` with a `lib.data.Layout` must accept a `Const` as a field value in a mapping reset initializer, and its reset must reflect that constant's value.
