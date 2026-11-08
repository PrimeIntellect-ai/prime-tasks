DEFAULT column attribute support for CREATE TABLE
```sql
CREATE TABLE Foo (
  id INTEGER DEFAULT 1
);
```

For now, create sql query is accepted but not working.
Modification in [row.rs](https://github.com/gluesql/gluesql/blob/main/src/data/row.rs) is required.
