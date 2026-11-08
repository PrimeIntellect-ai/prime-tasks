[ENH] support .query()-style strings in df.update_where()
Given the `update_where` example:

```python
# The dataframe must be assigned to a variable first.
data = {
    "a": [1, 2, 3, 4],
    "b": [5, 6, 7, 8],
    "c": [0, 0, 0, 0]
}
df = pd.DataFrame(data)
df = (
    df
    .update_where(
        condition=(df['a'] > 2) & (df['b'] < 8),
        target_column_name='c',
        target_val=10)
    )
```

It would be nice to be able to use `.query`'s style instead to avoid having to use `df.pipe()` if `df` has been modified somewhere along your method chain block:

```python
df = (
    pd.DataFrame(data)
    .update_where(
        condition='a > 2 and b < 8',
        target_column_name='c',
        target_val=10)
    )
)
```
