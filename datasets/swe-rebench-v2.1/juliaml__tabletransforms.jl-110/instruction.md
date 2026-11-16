Add option to rename columns during selection
A nice feature of the DataFrames.jl select function is that it allows in-place renaming:

```julia
select(df, :x => :y, :a => :b)
```

Currently, we have to write a `Select(:x, :a)` and then use `Rename(:x => :y, :a => :b)` on the result. Maybe we could introduce a `SelectRename` transform or generalize the `Select` to accept renaming.

### Additional contract requirements

- `Select` accepts one or more renaming pairs, for example `Select(:a => :x, :b => :y)`. The left-hand side of each pair is a column identifier (a `Symbol`, `String` or integer) and the right-hand side is the new column name given as a `Symbol` or an `AbstractString`. The selected columns keep the order in which they are given and are renamed to the supplied names.
- A `Select` constructed without renaming has `newnames = nothing`.
- The compact display of a `Select` transform is `Select([:a, :b], [:x, :y])` for a renaming selection and `Select([:a, :b, :c], nothing)` otherwise. Its full `MIME"text/plain"` display is

  ```
  Select transform
  ├─ colspec = [:a, :b]
  └─ newnames = [:x, :y]
  ```

  for a renaming selection and

  ```
  Select transform
  ├─ colspec = [:a, :b, :c]
  └─ newnames = nothing
  ```

  otherwise.
- `TableTransforms.TableSelection(table, newnames, select)` builds a column-selection view of `table` whose column names are `newnames` and whose columns are the original columns named by `select`. It throws `AssertionError` when a name in `select` is not a column of `table`. The view implements the Tables.jl interface (`istable`, `columnaccess`, `rowaccess`, `getcolumn`, `columnnames`, `schema`, `materializer`).
- `apply(transform::Select, table)` returns a tuple `(selection, cache)` where `selection` is a `TableSelection` with the renamed columns, and `revert(::Select, newtable, cache)` restores the original table with its original column names and order.
