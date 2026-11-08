Preserve the underlying pandas DataFrame's index in initialization of Woodwork data structure
- As a user, I would like Woodwork to preserve the underlying pandas DataFrame's index if I did not specify a specific `index` column to use. Right now, in WW 0.0.8 and 0.0.9, the index is replaced with `RangeIndex`. However, in EvalML, we want to preserve the user input's index. This is currently tricky to do without adding a new index column and then removing it.

Talked to @tamargrey about https://github.com/alteryx/woodwork/pull/464; we agreed a happy balance could be:
- If user doesn't specify `index` parameter in initialization of WW DataTable, use underlying Index.
- If user later sets `index` and then removes it, `RangeIndex` is a good default.

#### Code Example

```python
X_df = pd.DataFrame([0, 1, 2, 3, 4], index=list(range(-5, 0)))
X_ww = ww.DataTable(X_df)
assert X_ww.to_dataframe().index == list(range(-5, 0))
```
