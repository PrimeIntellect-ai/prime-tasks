sql:insert and table:insert should not require the primary key, instead should return it.
Hello just testing the project, looks great just have some comments on the insert behavior.
[stmt:step](https://www.sqlite.org/c3ref/step.html) returns `SQLITE_ROW` after an insert from where the id of the inserted row is retrieved, there's also [last_insert_row_id](https://www.sqlite.org/c3ref/last_insert_rowid.html). Therefore the primary key of a table shouldn't be required when inserting.

> Each entry in most SQLite tables (except for WITHOUT ROWID tables) has a unique 64-bit signed integer key called the "rowid". The rowid is always available as an undeclared column named ROWID, OID, or _ROWID_ as long as those names are not also used by explicitly declared columns. **If the table has a column of type INTEGER PRIMARY KEY then that column is another alias for the rowid.**
