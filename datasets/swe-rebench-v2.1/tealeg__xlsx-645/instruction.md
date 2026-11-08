Panic on xlsx.Save
@tealeg linke in #638 we have still a problem

PANIC File Storage

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x28 pc=0x6cc17f]

goroutine 1 [running]:
github.com/tealeg/xlsx/v3.(*Sheet).prepWorksheetFromRows.func1.1(0xc000c2f200, 0x1, 0x0)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:610 +0x1df
github.com/tealeg/xlsx/v3.(*MemoryRow).ForEachCell.func1(0x9, 0xc000c2f200, 0x0, 0x0)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/memory.go:94 +0x84
github.com/tealeg/xlsx/v3.(*MemoryRow).ForEachCell(0xc00095cff0, 0xc00050fe90, 0xc00000e6d0, 0x1, 0x1, 0xc000045400, 0x6b8854)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/memory.go:98 +0x10a
github.com/tealeg/xlsx/v3.(*Row).ForEachCell(...)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/row.go:116
github.com/tealeg/xlsx/v3.(*Sheet).prepWorksheetFromRows.func1(0xc000b16540, 0xc000b16540, 0x17)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:643 +0x102
github.com/tealeg/xlsx/v3.(*Sheet).ForEachRow(0xc00067ea80, 0xc000045518, 0xc0000454e8, 0x1, 0x1, 0xc0003bdc20, 0x796ee8)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:187 +0x283
github.com/tealeg/xlsx/v3.(*Sheet).prepWorksheetFromRows(0xc00067ea80, 0xc0036d19e0, 0x0, 0xc000268600, 0xc000226080)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:646 +0x11b
github.com/tealeg/xlsx/v3.(*Sheet).MarshalSheet(0xc00067ea80, 0x7db7a0, 0xc000268640, 0xc00050f800, 0xc00017cc60, 0x0, 0x0, 0x10)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:861 +0x1e9
github.com/tealeg/xlsx/v3.(*File).MarshallParts(0xc000182180, 0xc000045d40, 0x1000, 0xc00022d000)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/file.go:472 +0x84f
github.com/tealeg/xlsx/v3.(*File).Write(0xc000182180, 0x7dc3a0, 0xc00000e0c8, 0xc0000001b6, 0xc00000e0c8)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/file.go:158 +0xef
github.com/tealeg/xlsx/v3.(*File).Save(0xc000182180, 0x790555, 0x65, 0xc0036d18c0, 0x0)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/file.go:141 +0x16d
main.main()
        /home/josef/Dokumente/git/rentonion/main.go:94 +0x558
exit status 2
```

PANIC Memory Storage
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x28 pc=0x6cc1df]

goroutine 1 [running]:
github.com/tealeg/xlsx/v3.(*Sheet).prepWorksheetFromRows.func1.1(0xc000a870e0, 0x1, 0x0)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:610 +0x1df
github.com/tealeg/xlsx/v3.(*MemoryRow).ForEachCell.func1(0x9, 0xc000a870e0, 0x0, 0x0)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/memory.go:94 +0x84
github.com/tealeg/xlsx/v3.(*MemoryRow).ForEachCell(0xc0006d4ae0, 0xc001b407b0, 0xc0000a6ac0, 0x1, 0x1, 0xc00007d3f8, 0x6b88b4)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/memory.go:98 +0x10a
github.com/tealeg/xlsx/v3.(*Row).ForEachCell(...)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/row.go:116
github.com/tealeg/xlsx/v3.(*Sheet).prepWorksheetFromRows.func1(0xc0004b3500, 0xc0004b3500, 0x17)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:643 +0x102
github.com/tealeg/xlsx/v3.(*Sheet).ForEachRow(0xc0004c8480, 0xc00007d510, 0xc00007d4e0, 0x1, 0x1, 0xc000e7b8c0, 0x797068)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:187 +0x283
github.com/tealeg/xlsx/v3.(*Sheet).prepWorksheetFromRows(0xc0004c8480, 0xc004265320, 0x0, 0xc00005c000, 0xc002864080)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:646 +0x11b
github.com/tealeg/xlsx/v3.(*Sheet).MarshalSheet(0xc0004c8480, 0x7db920, 0xc00005c0f0, 0xc001b40330, 0xc000108b00, 0x0, 0x0, 0x10)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/sheet.go:861 +0x1e9
github.com/tealeg/xlsx/v3.(*File).MarshallParts(0xc00010e180, 0xc00007dd38, 0x1000, 0xc000185000)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/file.go:472 +0x84f
github.com/tealeg/xlsx/v3.(*File).Write(0xc00010e180, 0x7dc520, 0xc0000a6208, 0xc0000001b6, 0xc0000a6208)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/file.go:158 +0xef
github.com/tealeg/xlsx/v3.(*File).Save(0xc00010e180, 0x7906d5, 0x65, 0xc004265200, 0x0)
        /home/josef/go/pkg/mod/github.com/tealeg/xlsx/v3@v3.2.2/file.go:141 +0x16d
main.main()
        /home/josef/Dokumente/git/rentonion/main.go:94 +0x579
```

CODE:

```go
// open an existing file
	wbFile, err := xlsx.OpenFile(fileToOpen, xlsx.UseMemoryCellStore) // which Store we use make no difference...
	if err != nil {
		panic(err)
	}

	// wbFile now contains a reference to the workbook
	// show all the sheets in the workbook
	fmt.Println("Sheets in this file:")
	for i, sh := range wbFile.Sheets {
		fmt.Println(i, sh.Name)
	}
	fmt.Println("----")

	sheetName := "Geräte"
	sh, ok := wbFile.Sheet[sheetName]
	if !ok {
		fmt.Println("Sheet does not exist")
		return
	}
	fmt.Println("Max row in sheet:", sh.MaxRow)
	//err = sh.ForEachRow(rowVisitor)
	//fmt.Println("Err=", err)

	time.Sleep(1 * time.Second)

	cell, err := sh.Cell(2, 107)
	if err != nil {
		panic(err)
	}
	colNum, rowNum, _ := xlsx.GetCoordsFromCellIDString("DD3000")
	fmt.Println("DD3:", cell.Formula())
	cell, err = sh.Cell(rowNum, colNum)
	if err != nil {
		panic(err)
	}
	cell.SetInt64(39491)

	err = wbFile.Save(fileToOpen + "_demo.xlsx") // line 94
	if err != nil {
		panic(err)
	}
```
