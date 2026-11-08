Generated columns with `stored` in SQLite are not marked as generated
**Description**
Generated columns are not reported as such by database metadata.

**To Reproduce**
Create the following table with SQLite :

```sql
create table foo (
  id integer primary key,
  bar int not null generated always as (id + 1) stored
);
```

On the `bar` column `IS_GENERATEDCOLUMN` is `NO` with `DatabaseMetaData.getColumns`. Without the stored keyword, it is `YES`.

**Expected Behavior**
On the `bar` column `IS_GENERATEDCOLUMN` should be `YES` with `DatabaseMetaData.getColumns`.


**Additional Context**
See [JDBC3DatabaseMetaData](https://github.com/xerial/sqlite-jdbc/blob/99aa8d9e41113d6bec2f77e0084a328cacbc98c7/src/main/java/org/sqlite/jdbc3/JDBC3DatabaseMetaData.java#L1081). [HIDDEN]

### Additional contract requirements

- For the reproduced table, `DatabaseMetaData.getColumns` must report the stored generated `bar` column as `IS_GENERATEDCOLUMN=YES` and the ordinary `id` column as `IS_GENERATEDCOLUMN=NO`.
