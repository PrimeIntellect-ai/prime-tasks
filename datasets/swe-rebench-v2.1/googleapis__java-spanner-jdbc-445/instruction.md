NullPointerException when querying structs
Queries that select an array of structs cause a NullPointerException in the JDBC driver. For example the following query cannot be executed using the JDBC driver:

```sql
WITH points AS
  (SELECT [1, 5] as point
   UNION ALL SELECT [2, 8] as point
   UNION ALL SELECT [3, 7] as point
   UNION ALL SELECT [4, 1] as point
   UNION ALL SELECT [5, 7] as point)
SELECT ARRAY(
  SELECT STRUCT(point)
  FROM points)
  AS coordinates;
```

### Additional contract requirements

- Add a static factory method `JdbcArray createArray(String typeName, Object[] elements)` in `com.google.cloud.spanner.jdbc.JdbcArray`. It creates a `JdbcArray` for the given SQL type name and element values. For the type name `"STRUCT"` the elements are supplied as a `Struct[]`.
- `JdbcArray.getBaseType()` returns the `java.sql.Types` code of the array's element type; for an array of structs this is `Types.STRUCT`.
- `JdbcArray.getArray()` returns the array elements as a native Java array; for an array of structs the result can be cast to `Struct[]`.
- `JdbcArray.getResultSet()` throws `java.sql.SQLFeatureNotSupportedException` for an array of structs.
