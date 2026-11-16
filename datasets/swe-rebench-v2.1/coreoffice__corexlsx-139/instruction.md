Unable to sort columns by intValue
**Version**

version 0.13.0

**Description of the bug**

when sorting columns, [HIDDEN], then sorting columns is not accurate (column 'AB' is lower than 'B' and should be greater) (order is : A ; B ; C ; ... ; Y; Z; AA; AB ; ...)

**Steps to reproduce**

        row.cells.sorted(by: {$0.reference.column < $1.reference.column}).forEach({cell in
            let cellData: CellValue = CellValue(row: row.reference, reference: cell.reference, type: cell.type, initialValue: cell.value, dateValue: cell.dateValue, sharedString: cell.stringValue(self.sharedStrings))
            cellDataArray.append(cellData)
        })

**Expected behavior**

- being able to extend in order to access ColumnReference intValue which is private in this version
[HIDDEN]


**Additional context**

Thanks for watching this !

### Additional contract requirements

- Comparing `ColumnReference` values must follow Excel's column order rather than lexicographic label order; for example, `AB` must compare greater than `B`.
