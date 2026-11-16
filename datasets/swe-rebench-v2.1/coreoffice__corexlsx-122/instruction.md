archiveEntryNotFound error
**Version**

0.12.0

**Description of the bug**

An `archiveEntryNotFound` error is thrown for certain files (but I couldn't figure out what exactly causes the issue)

**Steps to reproduce**

1. Load the file attached bellow (`let file = XLSXFile(filepath: tableFilePath)`)
2. Call `parseSharedStrings`

**File for reproduction**

Test.xlsx
https://tools.hb.bizmrg.com/Test.xlsx

### Additional contract requirements

- `XLSXFile.parseSharedStrings()` returns an optional `SharedStrings?` value.
- When the workbook archive does not contain a `xl/sharedStrings.xml` part, `parseSharedStrings()` returns `nil` instead of throwing an `archiveEntryNotFound` error.
- Parsing or I/O errors other than the missing shared-strings part are still thrown.
