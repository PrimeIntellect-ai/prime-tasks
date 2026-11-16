Parsing fails in presence of significant space pattern match as a non-last parameter
scalameta 4.8.7 can't parse the following valid Scala code:

```scala
val component =
  List(1,2,3)
    .map: (props) =>
      TableOptions(
        getRowId = (row, _, _) =>
          row.value match
            case Left(HeaderRow(rowId, _)) => rowId
            case Right(stepRow)            => stepRow.step.rowId,
        onColumnSizingChange = dynTable.onColumnSizingChangeHandler
      )
```

It fails on line 3 with `; expected but => found`.

However, it works fine if the last parameter (`onColumnSizingChange`) is moved above `getRowId`, or if braces are added to the pattern match.

In other words, both of these work:
```scala
val component =
  List(1,2,3)
    .map: (props) =>
      TableOptions(
        onColumnSizingChange = dynTable.onColumnSizingChangeHandler,
        getRowId = (row, _, _) =>
          row.value match
            case Left(HeaderRow(rowId, _)) => rowId
            case Right(stepRow)            => stepRow.step.rowId
      )
```

```scala
val component =
  List(1,2,3)
    .map: (props) =>
      TableOptions(
        getRowId = (row, _, _) =>
          row.value match {
            case Left(HeaderRow(rowId, _)) => rowId
            case Right(stepRow)            => stepRow.step.rowId
          },
        onColumnSizingChange = dynTable.onColumnSizingChangeHandler
      )
```


(Thanks @keynmol for helping isolate the issue).
