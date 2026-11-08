[BUG] `qml.equal` ignore in-place inversion
Currently, we have:
```
>>> qml.equal(qml.RX(1.0, wires=0), qml.RX(1.0, wires=0).inv())
True
```

If two operations are inverses of each other, they should not be equal.
