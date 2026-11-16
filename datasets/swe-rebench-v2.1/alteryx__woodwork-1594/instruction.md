Renaming columns switches the schema column order
When renaming woodwork columns the order of columns in the schema also changes. Is this intended behavior?

```python
df = pd.DataFrame({"A": [1, 2, 3], "B": [1, 2, 3], "C": [1, 2, 3]})
df.ww.init()

df_renamed = df.ww.rename(rename)

assert df_renamed.ww.schema.columns == df.ww.schema.columns
```

### Additional contract requirements

- Renaming columns preserves their positions in the schema: substitute each renamed column’s new name at its original position, leaving unrenamed names in place. The schema reflects the new names, so the full schema mappings need not be equal before and after renaming.
