How to apply text alignment to all header columns?
I love my table header row to have center-aligned text, like this

```
╭───┬──────┬──────────────┬──────────────────────────────┬───────────────┬─────────┬────────────────┬──────────────────────╮
│ # │ Name │ Container ID │             Image            │      Kind     │  State  │  IPv4 Address  │     IPv6 Address     │
├───┼──────┼──────────────┼──────────────────────────────┼───────────────┼─────────┼────────────────┼──────────────────────┤
│ 1 │ srl  │ 7faefde8ee2e │ ghcr.io/nokia/srlinux:latest │ nokia_srlinux │ running │ 172.20.20.2/24 │ 3fff:172:20:20::2/64 │
╰───┴──────┴──────────────┴──────────────────────────────┴───────────────┴─────────┴────────────────┴──────────────────────╯
```

The problem is, that it seems setting the text alignment of the header columns is only possible with

```
table.SetColumnConfigs()
```

which needs to know either the column names, or indexes. I compile the table dynamically, so I might now know the names of the rows ahead of time.

At the same time, it seems there is no `table.AddColumnConfigs()` that would not overwrite the slice of column configs. How could I dynamically add the column config iterating over the slice of `table.Row`?

### Additional contract requirements

The `table` package must expose table-wide default text alignment through the exported `FormatOptions` struct, which is reachable as `tw.Style().Format` on a `table.Writer`:

- `HeaderAlign text.Align` and `HeaderVAlign text.VAlign`: default horizontal and vertical alignment for header cells.
- `FooterAlign text.Align` and `FooterVAlign text.VAlign`: default horizontal and vertical alignment for footer cells.
- `RowAlign text.Align` and `RowVAlign text.VAlign`: default horizontal and vertical alignment for data-row cells.

Setting these fields must change the rendered alignment of the corresponding header, footer, and data cells. Per-column configuration set through `SetColumnConfigs` takes precedence over these table-wide defaults.
