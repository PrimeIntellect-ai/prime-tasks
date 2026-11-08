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

When a workbook does not contain the shared-strings archive part, calling `parseSharedStrings()` must complete successfully rather than fail with `archiveEntryNotFound`; it may return no value or an empty shared-strings value. When the part is present and valid, its contents remain available through the returned value, and malformed shared-strings XML remains a parsing error.
