Wrong shape computed for `range(0, 10, 3)`
```
>>> list(range(0, 10, 3))
[0, 3, 6, 9]
>>> Shape.cast(range(0, 10, 3))
unsigned(3)
>>> Const(9, Shape.cast(range(0, 10, 3)))
(const 3'd1)
```
