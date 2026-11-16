SetColAutoWidth has an issue
Hi,

there is some issue with: SetColAutoWidth. when i start with i == 0 it has an error - the xlsx file is corrupted. when i do: sheet.SetColAutoWidth(1, xlsx.DefaultAutoWidth) it sets the first col. also sheet.SetColAutoWidth(5, xlsx.DefaultAutoWidth) corruptes the xlsx file.

```
file := xlsx.NewFile()
sheet, err := file.AddSheet("Demo")
if err != nil {
	return nil, nil
}
defer sheet.Close()
header := createHeader() // returns 5 col names

row := sheet.AddRow()
row.SetHeight(16)

for i, headerCol := range header {
	cell := row.AddCell()
	cell.Value = headerCol
	sheet.SetColAutoWidth(i, xlsx.DefaultAutoWidth)
}
```

### Additional contract requirements

- `SetColAutoWidth` uses one-based column indices: `1` refers to the first column and `5` to the fifth. Callers iterating with zero-based indices should account for this mapping.
- The automatic width must be calculated from the target column's contents, and setting it must not corrupt the workbook.
