Inconsistent truncation/wrapping behavior for multiline text cells
## Issue

Cell truncation and wrapping behaves inconsistently/unintuitively in the case of cells with newlines. See the example below or as a [gist](https://gist.github.com/kalzoo/8b6c7f557b1715d60dc97dcbffc91986):

```rust
fn main() {
    let mut builder = tabled::builder::Builder::default();

    let cell_data = (0..10).map(|v| format!("#{v:02}")).collect::<Vec<_>>().join("\n");
    builder.add_record(vec![cell_data.clone(), cell_data.clone()]);

    let common_table = builder.build();

    let mut truncate_table = common_table.clone();
    truncate_table.with(tabled::Width::truncate(12));
    println!("Narrow data, truncation:");
    println!("{truncate_table}");

    let mut wrap_table = common_table.clone();
    wrap_table.with(tabled::Width::wrap(12));
    println!("Narrow data, wrapping:");
    println!("{wrap_table}");

    // Wider data, same table, behavior changes
    let mut builder = tabled::builder::Builder::default();
    let cell_data = (0..10).map(|v| format!("#{v:05}")).collect::<Vec<_>>().join("\n");
    builder.add_record(vec![cell_data.clone(), cell_data.clone()]);

    let common_table = builder.build();

    let mut truncate_table = common_table.clone();
    truncate_table.with(tabled::Width::truncate(12));
    println!("Wide data, truncation:");
    println!("{truncate_table}");

    let mut wrap_table = common_table.clone();
    wrap_table.with(tabled::Width::wrap(12));
    println!("Wide data, wrapping:");
    println!("{wrap_table}");
}
```

## Truncation

The data in the first two examples are "narrow" in that they are all 3 characters wide. The gist has two more examples with 5-character-wide data.

Note: the data is the same in both cells below. When it fits without truncation, all lines are displayed; but if the first line is truncated, the lines below it are removed in their entirety. I might expect `#0`, `#0`, `#0` in that first column.

```
Narrow data, truncation:
+----+-----+
| #0 | #00 |
|    | #01 |
|    | #02 |
|    | #03 |
|    | #04 |
|    | #05 |
|    | #06 |
|    | #07 |
|    | #08 |
|    | #09 |
+----+-----+
```

## Wrapping

The only difference from the table above is the use of wrapping. Note that the newline characters themselves appear to be counted, when they should instead _reset_ the count of characters allowed before the next wrap. So, even though the input data has no empty lines, the table cell does (such as between #03 and #04), and some lines wrap early (like `#\n01`):

```
+----+-----+
| #0 | #00 |
| 0  | #01 |
| #  | #02 |
| 01 | #03 |
|    | #04 |
| #0 | #05 |
| 2  | #06 |
| #  | #07 |
| 03 | #08 |
|    | #09 |
| #0 |     |
| 4  |     |
| #  |     |
| 05 |     |
|    |     |
| #0 |     |
| 6  |     |
| #  |     |
| 07 |     |
|    |     |
| #0 |     |
| 8  |     |
| #  |     |
| 09 |     |
+----+-----+
```

# Possible fix

Without yet investigating the code, it appears that cell contents are treated as a single line for truncation & wrapping logic; however, each individual line within a cell should be wrapped or truncated independently.

The user can work around this by registering each line of a cell as its own independent cell, which will be clumsy to do (because each cell would need special formatting rules to decide which borders to render). If that's the intended behavior though, a note in the readme about multiline text cell behavior might help others as well.

Thanks!

### Additional contract requirements

- When a multiline cell is truncated (that is, at least one of its lines exceeds the target width), the configured suffix is appended to every line of the cell, including lines that individually fit within the target width. For example, `Width::truncate(1).multiline().suffix(".")` renders the cell `"H\nel\nlo World"` as three lines, each equal to `"."`.
- The multiline handling required by this task applies to truncation (`Truncate::multiline()`). The wrapping behavior of `Wrap` for multiline cells is not modified by this task.
