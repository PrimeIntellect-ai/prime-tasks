Unshaped enumeration values don't work when used in a constant initializer
To reproduce:

```python
from amaranth.lib import enum, data

class QSPIMode(enum.Enum):
    PutX1 = 0

data.StructLayout({"mode": QSPIMode}).const({"mode": QSPIMode.PutX1})
```

```
  File ".../bug.py", line 6, in <module>
    data.StructLayout({"mode": QSPIMode}).const({"mode": QSPIMode.PutX1})
  File ".../python3.12/site-packages/amaranth/lib/data.py", line 232, in const
    key_value = hdl.Const(key_value, cast_field_shape)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File ".../python3.12/site-packages/amaranth/hdl/_ast.py", line 1551, in __call__
    return super().__call__(value, shape, **kwargs, src_loc_at=src_loc_at + 1)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File ".../python3.12/site-packages/amaranth/hdl/_ast.py", line 1601, in __init__
    value = int(operator.index(value))
                ^^^^^^^^^^^^^^^^^^^^^
TypeError: 'QSPIMode' object cannot be interpreted as an integer
```

### Additional contract requirements

`Const` accepts an enumeration member as a constant value. If no shape is provided, the constant uses the shape declared by the enumeration type; if a shape is provided, that shape is used. The constant's integer value is the enumeration member's underlying value. `StructLayout.const` also accepts enumeration members as field initializers, encoding each member's underlying integer value using the shape supplied by its field layout.
