Col.SetStyle() not effect
`

    file := xlsx.NewFile()
	sheet, err := file.AddSheet("Sheet1")
	if err != nil {
		fmt.Println(err.Error())
		return
	}

	sheet.Cell(0, 0).SetString("BBBBBB")
	colStyle := xlsx.NewStyle()
	colStyle.Fill.FgColor = "EEEEEE00"
	colStyle.Fill.PatternType = "solid"
	colStyle.ApplyFill = true

	col := xlsx.NewColForRange(10, 10)
	col.SetStyle(colStyle)
	sheet.SetColParameters(col)
	sheet.Cell(1, 1).SetStyle(colStyle)
	err = file.Save("E:/GoMod/xlsx/Tt/d.xlsx")
	if nil != err {
		fmt.Println(err.Error())
		return
	}
`

> d.xlsx

### Additional contract requirements

When a style is assigned to a column with `Col.SetStyle`, the saved XLSX workbook must retain that style for every column in the configured range, including when the style has no number format.
