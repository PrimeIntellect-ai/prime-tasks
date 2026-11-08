bug: `ArrowSeries.scatter` raises out of bound error
pyarrow backed series raises an out of bound error in scatter if `indices`:

- is not 0
- are not full length of the series

Repro:

```py
import narwhals as nw
import pyarrow as pa

tbl = pa.table({"a": [1, 2, 3], "b": [142, 124, 132]})
frame = nw.from_native(tbl, eager_only=True)
ser = frame["a"]

try:
    result = ser.scatter(1, 999)
except Exception as exc:
    print(exc)


try:
    result = ser.scatter([0, 2], [999, 888])
except Exception as exc:
    print(exc)
```

> Index 1 out of bounds
> Index 2 out of bounds
