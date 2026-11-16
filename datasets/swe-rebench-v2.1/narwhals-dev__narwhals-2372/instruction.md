[Bug]: `nw.len().over("column")` not working for pandas DataFrames
### Describe the bug

```python
df.with_columns(a_len_per_group=nw.len().over("b"))
```

Raises an exception when df native DataFrame is a pandas DataFrame while it works as expected when df native DataFrame is a polars DataFrame.

### Steps or code to reproduce the bug

```python
import pandas as pd
import narwhals as nw
df_native = pd.DataFrame({"a": [1, 2, 4], "b": ["x", "x", "y"]})
df = nw.from_native(df_native)
df.with_columns(a_len_per_group=nw.len().over("b"))
```

### Expected results

```
┌───────────────────────────────┐
|      Narwhals DataFrame       |
|-------------------------------|
|shape: (3, 3)                  |
|┌─────┬─────┬─────────────────┐|
|│ a   ┆ b   ┆ a_len_per_group │|
|│ --- ┆ --- ┆ ---             │|
|│ i64 ┆ str ┆ u32             │|
|╞═════╪═════╪═════════════════╡|
|│ 1   ┆ x   ┆ 2               │|
|│ 2   ┆ x   ┆ 2               │|
|│ 4   ┆ y   ┆ 1               │|
|└─────┴─────┴─────────────────┘|
└───────────────────────────────┘
```

### Actual results

It raises `KeyError: "Columns not found: 'len'"`

### Please run narwhals.show_version() and enter the output below.

```shell
System:
    python: 3.10.15 | packaged by conda-forge | (main, Sep 20 2024, 16:37:05) [GCC 13.3.0]
executable: /{redacted}/.venv/bin/python
   machine: Linux-5.10.0-34-cloud-amd64-x86_64-with-glibc2.31

Python dependencies:
     narwhals: 1.34.1
       pandas: 2.2.3
       polars: 1.24.0
         cudf:
        modin:
      pyarrow: 18.1.0
        numpy: 1.26.4
```

### Relevant log output

```shell

```
