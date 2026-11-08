Table.compareRows not working as expected
The static method `Table.compareRows` always returns `false` except for the last row. It happens even when we compare rows of the same table.
```
Table table = Table.read().csv(new File("data.csv"));
System.out.println(table.shape());

for(int i = 0; i < table.rowCount(); i++) {
    System.out.println("ROW " + i + ": "+ Table.compareRows(i, table, table));
}
```
Actual output:
```
data.csv: 5 rows X 2 cols
ROW 0: false
ROW 1: false
ROW 2: false
ROW 3: false
ROW 4: true
```
Expected output:
```
data.csv: 5 rows X 2 cols
ROW 0: true
ROW 1: true
ROW 2: true
ROW 3: true
ROW 4: true
```

### Additional contract requirements

- For a valid row index, `Table.compareRows(rowNumber, table1, table2)` reports whether the row at `rowNumber` in `table1` and the row at `rowNumber` in `table2` contain equal data.
- A row compared with itself is reported as equal.
- Two rows with the same values in every column are reported as equal, even when they belong to two different table objects.
- Rows that differ in at least one column value are reported as not equal.
- Rows from tables with a different number of columns are reported as not equal.
