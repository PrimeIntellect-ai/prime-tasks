Sometimes sqlmesh format and the ctrl + s button in the UI makes the code less readable (IMO) for mssql
The following rules from sqlmesh format reduces readability IMO:
* Adding "as column_name" after every column name
* No spaces between CTE's
* The adding of coalesce(varchar(max)) when casting: https://github.com/TobikoData/sqlmesh/issues/1815

I can see there's another "format/translation" layer, that encapsulates all schema, table and column names in "" (it probably does more), before the code ends up in the database.
Maybe some of the above rules can be added to that last layer to avoid messing with readability of the model files?

Here's an example showing some code becoming less readable:

```
MODEL (
  name new_schema.new_table_name,
  kind VIEW
);

WITH first_cte AS (
  SELECT
    foo,
    bar,
    baz,
    ham,
    a_very_long_column_name
  FROM source_schema.source_table1
),

WITH second_cte AS (
  SELECT
    foo_foo_foo,
    bar_bar_bar,
    an_even_longer_column_name
  FROM source_schema.source_table2
),

concat_me AS (
  SELECT
    second_cte.foo_foo_foo,
    second_cte.bar_bar_bar,
    concat(first_cte.a_very_long_column_name, second_cte.an_even_longer_column_name, 'post_fix') as something_concat
  FROM first_cte
  LEFT JOIN second_cte
    ON first_cte.foo = second_cte.foo_foo_foo
    AND first_cte.bar = second_cte.bar_bar_bar
),

something_to_union AS (
  SELECT
    foo_foo_foo,
    bar_bar_bar,
    something_concat
  FROM another_schema.another_table
),

unionized AS (
  SELECT * FROM concat_me
  UNION ALL
  SELECT * FROM something_to_union
)

SELECT
  *
FROM unionized
```


Becomes:
```
MODEL (
  name new_schema.new_table_name,
  kind VIEW
);

WITH first_cte AS (
  SELECT
    foo AS foo,
    bar AS bar,
    baz AS baz,
    ham AS ham,
    a_very_long_column_name AS a_very_long_column_name
  FROM source_schema.source_table1
), second_cte AS (
  SELECT
    foo_foo_foo AS foo_foo_foo,
    bar_bar_bar AS bar_bar_bar,
    an_even_longer_column_name AS an_even_longer_column_name
  FROM source_schema.source_table2
), concat_me AS (
  SELECT
    second_cte.foo_foo_foo AS foo_foo_foo,
    second_cte.bar_bar_bar AS bar_bar_bar,
    CONCAT(
      COALESCE(CAST(first_cte.a_very_long_column_name AS VARCHAR(MAX)), ''),
      COALESCE(CAST(second_cte.an_even_longer_column_name AS VARCHAR(MAX)), ''),
      COALESCE(CAST('post_fix' AS VARCHAR(MAX)), '')
    ) AS something_concat
  FROM first_cte
  LEFT JOIN second_cte
    ON first_cte.foo = second_cte.foo_foo_foo AND first_cte.bar = second_cte.bar_bar_bar
), something_to_union AS (
  SELECT
    foo_foo_foo AS foo_foo_foo,
    bar_bar_bar AS bar_bar_bar,
    something_concat AS something_concat
  FROM another_schema.another_table
), unionized AS (
  SELECT
    *
  FROM concat_me
  UNION ALL
  SELECT
    *
  FROM something_to_union
)
SELECT
  *
FROM unionized
```

### Additional contract requirements

- When formatting a model with consecutive CTEs, separate each CTE from the preceding one with whitespace after the comma. A blank line between CTEs is not required.
- When formatting a model expression containing `CAST(x as int)::int`, format it as `x::INT::INT`.
- When formatting SQL Server model source, do not add SQL Server translation wrappers such as `COALESCE` with `VARCHAR(MAX)` around casts or concatenations. Such dialect-specific transformations may appear in SQL produced for execution, but must not be introduced into the formatted model text.
