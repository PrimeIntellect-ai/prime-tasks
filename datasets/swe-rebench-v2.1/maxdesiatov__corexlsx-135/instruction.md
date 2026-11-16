Odd cell.s value
**Version**

0.13.0

**Description of the bug**

When querying a cell's "s" value, cell.s, defined in the documentation as
```swift
  // FIXME: Attribute "s" in a cell is an index into the styles table,
  // while the cell type "s" corresponds to the shared string table.
  // Can XMLCoder distinguish between an attribute and an
  // element having the same name?
```

Then querying the styles table as:
```swift
let styles = file.parseStyles()
styles.cellStyles[Int(cell.s)]

//or

styles.cellStyles?.items.first(where: {$0.builtinId == Int(cell.s ?? "") || $0.formatId == Int(cell.s ?? "")})

```
offers index out of range or nil in each respectively.


**Expected behavior**

I expected the cellsStyle table with index of cell.s to be the style sought.

### Additional contract requirements

A worksheet cell's `s` attribute is exposed as an optional integer `styleIndex`, independently of the cell's `t` type attribute (where `t="s"` denotes a shared-string cell). `Cell.format(in:)` must use that index to select the corresponding entry from the parsed stylesheet's cell-format list, so distinct valid indices can resolve to their corresponding entries.
