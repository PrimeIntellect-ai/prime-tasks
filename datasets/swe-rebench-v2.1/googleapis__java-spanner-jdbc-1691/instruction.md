[General] Datanucleus is incompatible with Cloud Spanner JDBC Driver >= 2.8.0 + GoogleSQL
#### Environment details

1. Specify the API at the beginning of the title. For example, "BigQuery: ...").
   General, Core, and Other are also allowed as types
2. OS type and version: Linux
3. Java version: 1.8
4.  version(s): `2.20.1`

#### Steps to reproduce

  1. I'm not at liberty to share the code, however, when attempting to use Datanucleus with CloudSpanner JDBC driver newer than 2.8.0 Datanucleus will be unable to get the type info from the JDBC connection string.

#### Code example

When Datanucleus attempts to load a JDBC connection, it will get the Type info from the connection, however, this type info is then immediately cast to a `short` in Datanucleus (1). However, with Google SQL and support for JSON it will crash upon trying to convert `100011` to a short, which is coming from the JSON vendor type number (2).

1. https://github.com/datanucleus/datanucleus-rdbms/blob/master/src/main/java/org/datanucleus/store/rdbms/schema/SQLTypeInfo.java#L137
2. https://github.com/googleapis/java-spanner-jdbc/blob/v2.15.5/src/main/java/com/google/cloud/spanner/jdbc/JsonType.java#L33

#### Stack trace
```
Caused by: com.google.cloud.spanner.jdbc.JdbcSqlExceptionFactory$JdbcSqlExceptionImpl: OUT_OF_RANGE: Value out of range for short: 100011
	at com.google.cloud.spanner.jdbc.JdbcSqlExceptionFactory.of(JdbcSqlExceptionFactory.java:247) ~[google-cloud-spanner-jdbc-2.20.1-single-jar-with-dependencies.jar:2.20.1]
	at com.google.cloud.spanner.jdbc.AbstractJdbcWrapper.checkedCastToShort(AbstractJdbcWrapper.java:237) ~[google-cloud-spanner-jdbc-2.20.1-single-jar-with-dependencies.jar:2.20.1]
	at com.google.cloud.spanner.jdbc.JdbcResultSet.getShort(JdbcResultSet.java:330) ~[google-cloud-spanner-jdbc-2.20.1-single-jar-with-dependencies.jar:2.20.1]
	at org.datanucleus.store.rdbms.schema.SQLTypeInfo.<init>(SQLTypeInfo.java:133) ~[datanucleus-rdbms-4.1.1.jar:?]
	... 59 more
```

The question is, can we either bring down the 100,000 addition to 32,000 ? Would that be a breaking change? This would ensure compatibility to those jdbc loaders who assume JDBC types are very small always.
