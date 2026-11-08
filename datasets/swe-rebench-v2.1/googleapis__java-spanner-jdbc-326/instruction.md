feat: support converting arrays to ResultSet
`java.sql.Array` has an optional method `getResultSet()`. This returns the array as a `ResultSet` and allows a client application to consume the array in the same way as consuming a normal result set. This method is currently not supported by the Cloud Spanner JDBC driver, which causes some generic applications to return error messages or not displaying (all types of) arrays correctly.

Supporting the `java.sql.Array#getResultSet()` method enhances the user experience in applications that try to consume arrays as `ResultSet`s.

### Additional contract requirements

- The `ResultSet` returned by `java.sql.Array#getResultSet()` contains one row per array element, ordered by the 1-based array index. It has exactly two columns: the first column holds the 1-based index, has JDBC type `BIGINT`, and is labeled `INDEX`; the second column holds the element value, has the JDBC type of the array's base type, and is labeled `VALUE`.
- `java.sql.Array#getResultSet(long startIndex, int count)` returns the elements beginning at the given 1-based `startIndex`, containing up to `count` elements (fewer if the array ends). A `count` of `0` returns an empty result set. A `startIndex` less than `1` or a `count` less than `0` throws a `SQLException` with error code `INVALID_ARGUMENT`.
