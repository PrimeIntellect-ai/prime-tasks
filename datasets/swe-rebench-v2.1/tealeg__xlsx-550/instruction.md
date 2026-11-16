Getting  xl/_rels/workbook.xml.rels not found in input xlsx.
I am getting the following errors:
2020/04/08 11:07:43 xl/_rels/workbook.xml.rels not found in input xlsx.

On adding debug info: https://github.com/tealeg/xlsx/blob/master/lib.go#L995

```go
	for _, v = range r.File {
		fmt.Printf("%v\n", v.Name)
		switch v.Name {
		case "xl/sharedStrings.xml" , `xl\sharedStrings.xml`:
```
I see the folowing file.Name:

_rels/workbook.xml.rels
_rels/.rels
xl/worksheets/data.xml
stylesheet.xml
[Content_Types].xml
workbook.xml


[HIDDEN]

```go
	for _, v = range r.File {
		[HIDDEN]
		switch v.Name {
		case "xl/sharedStrings.xml" , `xl\sharedStrings.xml`:
```

### Additional contract requirements

- The reader must successfully open workbooks whose metadata parts are stored at the package root rather than exclusively beneath `xl/`, including when the workbook relationships file is at `_rels/workbook.xml.rels`.
- When the workbook relationships file is missing, the error text must be exactly `OpenFile: ReadZip: ReadZipReader: workbook.xml.rels not found in input xlsx.`
