`table.is_empty()` on tables with only a header row
Hi, I run into a situation where I need to check if a table with a header row is empty. I notice that `table.is_empty()` returns false if the table has no data rows but merely a header row. However the function returns true if the table is indexed:

```rust
use tabled::{builder::Builder, settings::Style};

fn main() -> Result<()> {
    let mut builder = Builder::default();
    builder.set_header(["color", "vegetable", "contains"]);
    let builder = builder.index().column(1).name(None);
    let table = builder.build();
    assert!(table.is_empty());

    let mut builder = Builder::default();
    builder.set_header(["color", "vegetable", "contains"]);
    let table = builder.build();
    assert!(!table.is_empty());

    Ok(())
}
```
The difference seems to be caused by that `IndexBuilder` takes ["data length"](https://github.com/zhiburt/tabled/blob/master/tabled/src/builder/index_builder.rs#L229-L230) into consideration. Is this difference by-design or should non-indexed tables do the same too?

### Additional contract requirements

- A table that has a header row but no data rows is not empty: `Table::is_empty()` returns `false` for such a table, both when the table is built directly and when it is built through an index.
