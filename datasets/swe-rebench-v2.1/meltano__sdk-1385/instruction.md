bug: column collations should be ignored during SQL type comparisons (SQL Server)
### Singer SDK Version

0.11.1

### Python Version

3.10

### Bug scope

Targets (data type handling, batching, SQL object generation, etc.)

### Operating System

Mac

### Description

SQL Server target: Initial load of a table with a varchar column works nicely, but on second write, the loader fails with a ValueError, after attempting to change column types. In the example, a PG source table with a VARCHAR(64) column:

`ValueError: Unable to merge sql types: VARCHAR(64) COLLATE "SQL_Latin1_General_CP1_CI_AS", VARCHAR(64)`

My interpretation is that the target initially ran a create table statement with a VARCHAR(64) column, SQL Server added the collation as a detail, but when inserting again the target interprets varchar with the added collation as a different column type than VARCHAR(64) and tries to alter it, but fails.

An ugly fix is to explicitly declare the collation on table creation: https://github.com/radbrt/target-mssql/blob/37544ad6306095b66bef9f01d35211f486b9bf77/target_mssql/sinks.py#L262


### Code

_No response_

### Additional contract requirements

- `SQLConnector.remove_collation(column_type)` is a static method on `singer_sdk.connectors.sql.SQLConnector`. Given a SQLAlchemy column type, it removes the `collation` attribute (setting it to `None`) and returns the previous collation string; if the type has no collation set, it returns `None`.
- `SQLConnector.update_collation(column_type, collation)` is a static method on `singer_sdk.connectors.sql.SQLConnector`. When the given column type has a `collation` attribute and a non-null `collation` value is supplied, it sets the attribute to that value.
- When an existing column's SQL type differs from the requested SQL type only by a collation, the two types must be treated as the same type, so no column alteration is attempted.
