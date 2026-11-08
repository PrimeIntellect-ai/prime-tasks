Support set operations on selectors
We currently have selectors: https://narwhals-dev.github.io/narwhals/api-reference/selectors/

E.g. you can do
```python
df.select(nw.selectors.numeric())
```

but you can't currently do
```python
df.select(nw.selectors.numeric() - nw.selectors.by_dtype(nw.Int64))
```

This is fairly important, as:
- `df.select(nw.selectors.numeric(), ~nw.selectors.by_dtype(nw.Int64))` might raise due to duplicate column names
- using `df.schema` isn't free on a lazyframe

### Additional contract requirements

- Selectors support the set operators `|` (union), `&` (intersection), `-` (difference) and `~` (complement). When the operands are selectors, the result is a selector whose selected columns are the corresponding set operation over the columns selected by its operands.
- When the right-hand operand of `|`, `&` or `-` is not a selector, the operator applies the corresponding expression operation to the selected columns.
- `narwhals.selectors` exposes a public `Selector` class for column selectors.
- `narwhals.selectors.all()` returns a `Selector` that selects every column of a dataframe.
