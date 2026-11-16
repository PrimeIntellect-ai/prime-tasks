Add `Unit` transform to convert units
The transform should behave like `uconvert` with column selections.

### Additional contract requirements

The default display of a `Unit` transform is part of the public contract. For
`T = Unit(:a => u"m", [:b, :c] => u"s")`:

- `sprint(show, T)` must equal exactly:

  `Unit(selectors: ColumnSelector[:a, [:b, :c]], units: Units[m, s])`

- `sprint(show, MIME("text/plain"), T)` must equal exactly:

```
Unit transform
├─ selectors: ColumnSelectors.ColumnSelector[:a, [:b, :c]]
└─ units: Unitful.Units[m, s]
```
