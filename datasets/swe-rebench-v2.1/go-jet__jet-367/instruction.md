ProjectionList{ColumnList{...}}.As("some_alias")  results in no columns being rendered in the SQL
**Describe the bug**

ProjectionList.As method drops ColumnList columns.

**Environment (please complete the following information):**
 - OS: macosx
 - Database: mysql
-  Database driver: github.com/go-sql-driver/mysql
 - Jet version v2.11.1

**Code snippet**

```go
strain := table.Strain
selects := mysql.ProjectionList{strain.AllColumns}.As("my_strain")
q := mysql.SELECT(selects).FROM(strain)
fmt.Println(q.DebugSql())
```
Output:
```
SELECT
FROM strain;
```

**Expected behavior**
I expected to see selected columns in the resulting SQL.
