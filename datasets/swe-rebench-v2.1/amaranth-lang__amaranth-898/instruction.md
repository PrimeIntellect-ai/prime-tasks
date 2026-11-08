Constructing a `signed(0)`-shaped Const fails with `ValueError`.
While a signed shape with width 0 is allowed by the model, it has unclear semantics, and attempting to actually use it results in errors:

```
>>> Const(0, signed(0))
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/mwk/amaranth/amaranth/hdl/ast.py", line 650, in __init__
    if self.signed and self.value >> (self.width - 1) & 1:
                       ~~~~~~~~~~~^^~~~~~~~~~~~~~~~~~
ValueError: negative shift count
```

### Additional contract requirements

- Signed shapes must have a positive width, so `signed(0)` is invalid. Accordingly, `Const(0, signed(0))` must be rejected with `TypeError`, rather than failing with a negative-shift `ValueError`.
