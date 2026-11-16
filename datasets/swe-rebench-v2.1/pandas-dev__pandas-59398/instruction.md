ENH: pd.concat with keys and ignore_index=True should raise
### Feature Type

- [ ] Adding new functionality to pandas

- [X] Changing existing functionality in pandas

- [ ] Removing existing functionality in pandas


### Problem Description

You can happily pass both of these arguments together, but the ignore_index=True call drops the keys, so it ends up being a moot point:

```python
In [1]: import pandas as pd

In [2]: df1 = pd.DataFrame([[0]])

In [3]: df2 = pd.DataFrame([[42]])

In [4]: pd.concat([df1, df2])
Out[4]:
    0
0   0
0  42

In [5]: pd.concat([df1, df2], keys=["df1", "df2"])
Out[5]:
        0
df1 0   0
df2 0  42

In [6]: pd.concat([df1, df2], keys=["df1", "df2"], ignore_index=True)
Out[6]:
    0
0   0
1  42
```

### Feature Description

pandas can raise that this combination of values does not make sense

### Alternative Solutions

status quo

### Additional Context

_No response_
