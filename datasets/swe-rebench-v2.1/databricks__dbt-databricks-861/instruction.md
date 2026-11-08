Enclose column name with backquote when appending a new column
### Describe the feature
When you define a model like the following and execute dbt run, new columns will be added if there are schema changes.
```
version: 2
models:
  - name: table
    config:
      materialized: incremental
      on_schema_change: append_new_columns
```

Internally, the following ALTER TABLE statement is executed:
```
alter table `db`.`schema`.`table`
    add columns (
        new_column string
    )
```
At this time, if the column name contains a hyphen, it will fail with the following error:
```
[INVALID_IDENTIFIER] The unquoted identifier column_name is invalid and must be back quoted as: `column_name`.
It would be helpful if you could either add an option to enclose column names with backticks when executing ALTER TABLE, or modify the SQL for ALTER TABLE itself.
```
It would be helpful if you could either add an option to enclose column names with backticks when executing ALTER TABLE, or modify the SQL for ALTER TABLE itself.


### Describe alternatives you've considered
Update alter table statement or add options whether enclosing columns with backquote or not.

### Additional context
NA

### Who will this benefit?
Users managing tables which has hyphen named columns will get the benefit.

### Are you interested in contributing this feature?
Yes, I'll support as much as possible.

### Additional contract requirements

- Add a public static method `DatabricksColumn.get_name(column: dict[str, Any]) -> str` in module `dbt.adapters.databricks.column`. It returns the column's `name` value wrapped in backticks when the column's `quote` flag is true, and the unchanged `name` value otherwise.
- Add a public static method `DatabricksColumn.format_remove_column_list(columns: list[DatabricksColumn]) -> str` in module `dbt.adapters.databricks.column`. It returns the backticked names of the given columns joined by `, `, and an empty string for an empty list.
- Add a public static method `DatabricksColumn.format_add_column_list(columns: list[DatabricksColumn]) -> str` in module `dbt.adapters.databricks.column`. It returns each column's backticked name followed by its data type, joined by `, `, and an empty string for an empty list.
- Add a public function `quote(name: str) -> str` in module `dbt.adapters.databricks.utils` that returns the given identifier wrapped in backticks.
- Add a public macro `databricks__alter_relation_add_remove_columns(relation, add_columns, remove_columns)` in the Databricks adapter macros. When it adds columns, the generated `ALTER TABLE ... ADD COLUMNS` statement must enclose each added column name in backticks.
