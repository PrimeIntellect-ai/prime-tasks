[Bug]: Summing empty Pandas DataFrame
### Describe the bug

`ValueError` when attempting to sum an empty Pandas DataFrame

### Steps or code to reproduce the bug

```py
import narwhals as nw
import pandas as pd
from narwhals import narwhalify

df = pd.DataFrame(
    {
        "name": ["John", "Doe", "Jane"],
    },
)


@narwhalify
def bla(df):
    df = df.filter(nw.col("name") == "Boo")
    df.with_columns(nw.col("name").sum())


bla(df)
```

### Expected results

An empty DataFrame

### Actual results

```
ValueError: Length of values (1) does not match length of index (0)
```

### Please run narwhals.show_version() and enter the output below.

```shell
System:
    python: 3.12.8 (main, Dec  6 2024, 19:42:06) [Clang 18.1.8 ]
executable: ...
   machine: macOS-15.2-arm64-arm-64bit

Python dependencies:
     narwhals: 1.20.1
       pandas: 2.2.3
       polars: 1.18.0
         cudf:
        modin:
      pyarrow:
        numpy: 2.2.1
```


### Relevant log output

_No response_

### Additional contract requirements

- For scalar reductions on an empty input, `max`, `mean`, and `min` must each return `None`.
