`rotate_*` crashes on 0-width `Value`
```
>>> a = Signal(0)
>>> a.rotate_left(1)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/mwk/amaranth/amaranth/hdl/ast.py", line 519, in rotate_left
    amount %= len(self)
ZeroDivisionError: integer modulo by zero
```

### Additional contract requirements

- For `Const(0, 0)`, each of `rotate_left(3)`, `rotate_left(-3)`, `rotate_right(3)`, and `rotate_right(-3)` must return a value of width zero.
