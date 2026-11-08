TypeError when accessing reset attribute from a Signal created with an ArrayLayout
Repro:
```python3
from amaranth import *
from amaranth.lib import data

layout = data.ArrayLayout(unsigned(1), 4)
a = Signal(layout, reset=[0,0,0,0])
a.reset
```

Output:
```
Traceback (most recent call last):
  File "/tmp/repro.py", line 7, in <module>
    a.reset
  File "/home/jf/src/amaranth/amaranth/lib/data.py", line 701, in __getattr__
    item = self[name]
           ~~~~^^^^^^
  File "/home/jf/src/amaranth/amaranth/lib/data.py", line 666, in __getitem__
    value = self.__target.word_select(key, Shape.cast(self.__layout.elem_shape).width)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/jf/src/amaranth/amaranth/hdl/ast.py", line 400, in word_select
    offset = Value.cast(offset)
             ^^^^^^^^^^^^^^^^^^
  File "/home/jf/src/amaranth/amaranth/hdl/ast.py", line 174, in cast
    raise TypeError("Object {!r} cannot be converted to an Amaranth value".format(obj))
TypeError: Object 'reset' cannot be converted to an Amaranth value
```
