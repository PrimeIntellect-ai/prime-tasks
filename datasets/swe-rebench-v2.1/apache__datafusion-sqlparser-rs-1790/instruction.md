Add support for OUTPUT Clause in TSQL (MS SQL) Merge statements
Add the end of a merge statement in T-SQL we can use an OUTPUT clause to write the changed rows to a table variable. This is often used in Data Warehouse workloads were we would like to track slowly changing dimensions.

A merge statement with the output clause could look like this:
```sql

MERGE dso.products AS t
USING dsi.products AS s
	ON s.ProductID = t.ProductID
WHEN MATCHED
	AND NOT (t.[ProductName] = s.[ProductName] OR (ISNULL(t.[ProductName], s.[ProductName]) IS NULL))
THEN
	UPDATE SET t.[ProductName] = s.[ProductName]

WHEN NOT MATCHED BY TARGET THEN
INSERT ([ProductID]
           ,[ProductName])
     VALUES
           (s.[ProductID]
           ,s.[ProductName])

WHEN NOT MATCHED BY SOURCE  THEN
	DELETE

OUTPUT $action, deleted.* INTO dsi.temp_products;
```

Currently this fails with the error `ParserError("Expected: WHEN, found: OUTPUT at Line: 112, Column: 1")`.

I will try to create a PR solving this issue, but any pointers on a good approach would be highly appreciated.

Thanks for the awesome crate btw.
