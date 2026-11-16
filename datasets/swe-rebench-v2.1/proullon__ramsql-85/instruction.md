Support true and false for values in argument values for Exec, Query

db.Exec("INSERT INTO table (id, hasBool) VALUES(?,?)", 0, true)

returns with no strconv error.

### Additional contract requirements

- `Exec` and `Query` must accept Go `bool` argument values (`true` and `false`) without returning a conversion error.
- Column names may be written in mixed case (for example `hasBool`) in `CREATE TABLE`, in the `INSERT` column list, and in `WHERE` predicates.
