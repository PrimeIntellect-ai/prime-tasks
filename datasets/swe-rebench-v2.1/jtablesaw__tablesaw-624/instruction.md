Create Better Column Not Found Error Message for Row
Ran into this today while using the library.

`row.getLong("colDoesNotExist")` throws an NPE. We should create a better error message. Possibly create a custom ColumnNotFoundException (unchecked) and use it project wide.

Current error message:

```
Exception in thread "main" java.lang.NullPointerException
	at tech.tablesaw.api.Row.getLong(Row.java:153)
	at com.ryancerf.tgo.steps.CreateInvoicesStep.createInvoices(CreateInvoicesStep.java:23)
	at com.ryancerf.tgo.Main.main(Main.java:40)
```

This error also occurs when the column name exists on the table, but the type is wrong. It would be nice if we searched the possible column names and gave the user the hint that they probably got the wrong `row.get` method.

If no one has grabbed this I should have time to work on it in a few days.

### Additional contract requirements

- When accessing missing column `col2` in table `myTable`, throw an `IllegalStateException` with the exact message `Column col2 is not present in table myTable`.
- When setting a time value on `col1` when it is a `LOCAL_DATE` column, throw an `IllegalArgumentException` with the exact message `Column col1 is of type LOCAL_DATE and cannot be cast to LOCAL_TIME. Use the method for LOCAL_DATE.`
