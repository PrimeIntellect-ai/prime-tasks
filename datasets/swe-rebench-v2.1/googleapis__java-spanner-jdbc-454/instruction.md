feat: Support getting/setting parameter and column values as com.google.cloud.spanner.Value instances
- The JDBC `ResultSet#getObject(int, Class type)` method should be able to return a `com.google.cloud.spanner.Value` instance
- The JDBC `PreparedStatement#setObject(int, Object value)` method should be able to accept a `com.google.cloud.spanner.Value` instance
