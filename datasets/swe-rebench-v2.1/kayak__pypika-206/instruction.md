Disable group by alias for Oracle and SQL Server dialects as it is not supported
MySQL, PostgreSQL (and Redshift I believe, as it is based on PostgreSQL) and Vertica support grouping by an alias defined in a select due to the order that certain parts of the query are executed:
https://stackoverflow.com/a/3841804/1224372

We should disable grouping by alias for SQL Server and Oracle dialects.
