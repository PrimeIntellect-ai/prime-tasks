feat: allow `ALTER TABLE` and `ALTER COLUMN` syntax to be overridden
### Feature scope

Targets (data type handling, batching, SQL object generation, etc.)

### Description

Snowflake uses a different syntax for altering columns than that implemented by the `_adapt_column_type` method on `SQLConnector`. To account for these differences, we could i) use a SQLAlchemy abstraction for altering columns (if one exists) or ii) provide an overridable public method for target developers to bring their own syntax.

### Additional contract requirements

`SQLConnector` must expose overridable public methods with these signatures:

- `get_column_alter_ddl(table_name, column_name, column_type)` for column type changes.
- `get_column_add_ddl(table_name, column_name, column_type)` for adding columns.
- `get_column_rename_ddl(table_name, column_name, new_column_name)` for renaming columns.

The corresponding column operations must obtain their DDL through these methods, allowing a target-specific implementation to supply its database's syntax.
