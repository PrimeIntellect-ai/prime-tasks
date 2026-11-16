Unable to sort columns by intValue
**Version**

version 0.13.0

**Description of the bug**

when sorting columns, sort is made with _value_ not _intValue_, then sorting columns is not accurate (column 'AB' is lower than 'B' and should be greater) (order is : A ; B ; C ; ... ; Y; Z; AA; AB ; ...)

**Steps to reproduce**

        row.cells.sorted(by: {$0.reference.column < $1.reference.column}).forEach({cell in
            let cellData: CellValue = CellValue(row: row.reference, reference: cell.reference, type: cell.type, initialValue: cell.value, dateValue: cell.dateValue, sharedString: cell.stringValue(self.sharedStrings))
            cellDataArray.append(cellData)
        })

**Expected behavior**

[HIDDEN]
[HIDDEN]


**Additional context**

Thanks for watching this !

### Additional contract requirements

- Column references must compare in Excel column order rather than raw-label order; for example, AB must compare greater than B.
