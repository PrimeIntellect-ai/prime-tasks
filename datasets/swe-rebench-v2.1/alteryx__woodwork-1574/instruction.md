Improve Woodwork error message for invalid init calls
If we do
```python
df = pd.Series(["90210", "60018", "10010"] * 100)
df.ww.init()
```
we get the following error:
```python
raise TypeValidationError(
woodwork.exceptions.TypeValidationError: Cannot initialize Woodwork. Series dtype 'object' is incompatible with PostalCode LogicalType. Try converting series dtype to 'category' before initializing or use the woodwork.init_series function to initialize.
```

If we were to follow the first recommendation, we get the following:
```python
df = pd.Series(["90210", "60018", "10010"] * 100).astype('category')
df.ww.init()
df.ww.schema
->
<ColumnSchema (Logical Type = Categorical) (Semantic Tags = ['category'])>
```
The second recommended action is correct, resulting in us getting a postal code logical type.

This issue tracks fixing this message so that users can get accurate inference on their datatables. In the case of series data, we should tell them to use `init_series` rather than `ww.init()`.

### Additional contract requirements

- Inferring the logical type of a Series whose values are valid postal codes must return the `PostalCode` logical type when the Series has a categorical dtype, as well as when it has a string dtype. `PostalCode` is available from `woodwork.logical_types`, and logical type inference is performed with `ww.type_system.infer_logical_type`.
