bug: `select` and `with_columns` don't always preserve column index name for pandas-like
```python
import pandas as pd
# import narwhals.stable.v1 as nw
import narwhals as nw

df = pd.DataFrame({'a': [1,2,3], 'b': [4,5,6]})
df.columns.name = 'foo'

print(nw.from_native(df).select(c=nw.col('a')+1).to_native())
print(nw.from_native(df).with_columns(c=nw.col('a')+1).to_native())
print(nw.from_native(df).to_native())
print(nw.from_native(df).to_native().assign(c=lambda df: df['a']+1))
```

outputs
```python
   c
0  2
1  3
2  4
   a  b  c
0  1  4  2
1  2  5  3
2  3  6  4
foo  a  b
0    1  4
1    2  5
2    3  6
foo  a  b  c
0    1  4  2
1    2  5  3
2    3  6  4
```

expected:
```python
foo  c
0    2
1    3
2    4
foo  a  b  c
0    1  4  2
1    2  5  3
2    3  6  4
foo  a  b
0    1  4
1    2  5
2    3  6
foo  a  b  c
0    1  4  2
1    2  5  3
2    3  6  4
```
