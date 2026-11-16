Index column with NaN will always return invalid schema
Our check in `get_invalid_schema_message` for whether the underlying index exactly matches the Woodwork index column uses [HIDDEN], which means NaNs will not evaluate to True, so we say that the schema is invalid.


```python
df = pd.DataFrame({'id':pd.Series([5,4,None,2], dtype='float64'), 'col':pd.Series(['b','b','b','d'], dtype='category')})
df.ww.init(index='id')
schema = df.ww.schema

assert not ww.is_schema_valid(df, schema)
```
We should add a test case with nans in the index column and add a fix that includes nans in the check.

This came up in a Featuretools test for `add_last_time_index` where we use `update_dataframe`.

### Additional contract requirements

- A dataframe whose Woodwork index column contains NaN values must still be considered schema-valid when its dataframe index matches that column, including at positions where both contain NaN values.
