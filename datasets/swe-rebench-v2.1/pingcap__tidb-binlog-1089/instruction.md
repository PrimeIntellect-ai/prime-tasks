Reparo: Add a support CreateView function
To add a function in Reparo tool when executing binlog data
As in the current version, it does not support "CREATE VIEW Statement".
The reparo main function treats it as invaild ddl type.

### Additional contract requirements

When a CREATE VIEW statement is executed from binlog data, the resulting DDL record must report the view's database and name as its database and table, including when the database is selected by a preceding USE statement.
