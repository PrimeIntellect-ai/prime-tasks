INSERT with more values is accepted
```sql
CREATE TABLE Test (id INTEGER);
INSERT INTO Test VALUES (100, 200);
```

below insertion query should report an error but it is accepted.
* [src/data/row.rs](https://github.com/gluesql/gluesql/blob/main/src/data/row.rs)

Current `Row` struct cares lack of values or columns but not handling more values properly.
