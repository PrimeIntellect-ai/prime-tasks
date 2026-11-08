``narwhals.Series`` repr output mangled for Polars-backed Series
```python
import pandas as pd
import polars as pl
import narwhals as nw


df = nw.from_native(pl.DataFrame({"col1": [None, 2], "col2": [3, 7]}))
s = df['col1']

print(s)
```
┌────────────────────┐
|  Narwhals Series   |
|--------------------|
|shape: (2,)         |
|Series: 'col1' [i64]|
|[                   |
|       null               |
|       2                  |
|]                   |
└────────────────────┘
```

[HIDDEN]

### Additional contract requirements

- The repr of a Polars-backed `narwhals.Series` must keep every line of the native Polars repr inside the surrounding box with its content intact: no tab characters may break the box, and every line of the box must have the same width.
