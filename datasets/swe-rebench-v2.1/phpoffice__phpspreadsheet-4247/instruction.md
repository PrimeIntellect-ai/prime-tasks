Bug in ReferenceHelper::duplicateStylesByRow()
This is:

```
- [x] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What is the current behavior?

When trying to insert a large amount of rows via `Worksheet::insertNewRowBefore()` it will throw an exception saying something like `Invalid cell coordinate AAAA1`. Tracing the issue via stack trace showed that there is a bug in `ReferenceHelper::duplicateStylesByRow()`:

````
    private function duplicateStylesByRow(Worksheet $worksheet, int $beforeColumn, int $beforeRow, string $highestColumn, int $numberOfRows): void
    {
        $highestColumnIndex = Coordinate::columnIndexFromString($highestColumn);
        for ($i = $beforeColumn; $i <= $highestColumnIndex; ++$i) {
            // Style
            $coordinate = Coordinate::stringFromColumnIndex($i) . ($beforeRow - 1);
            if ($worksheet->cellExists($coordinate)) {
                $xfIndex = $worksheet->getCell($coordinate)->getXfIndex();
                for ($j = $beforeRow; $j <= $beforeRow - 1 + $numberOfRows; ++$j) {
                    [HIDDEN]
                        $worksheet->getCell(Coordinate::stringFromColumnIndex($i) . $j)->setXfIndex($xfIndex);
                    }
                }
            }
        }
    }

````

[HIDDEN]

[HIDDEN]

### What are the steps to reproduce?

Tried to recreate a piece of sample code but did not get it done in a reasonable amount of time because it also depends on the Excel file and on the XfIndex (don't know what that is) of the cell. But the error is pretty obvious just looking at the code.

### What features do you think are causing the issue

- [ ] Reader
- [ ] Writer
- [ ] Styles
- [ ] Data Validations
- [ ] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Does an issue affect all spreadsheet file formats? If not, which formats are affected?

Can't say.

### Which versions of PhpSpreadsheet and PHP are affected?

Our version is 2.2.2, but looking at the code base at Github it is still present in the current version.

### Additional contract requirements

- When inserting rows, the operation must not fail with an invalid cell coordinate for valid row indices. Styles should remain associated with the correct cells, without being incorrectly applied to cells in other rows or columns.
