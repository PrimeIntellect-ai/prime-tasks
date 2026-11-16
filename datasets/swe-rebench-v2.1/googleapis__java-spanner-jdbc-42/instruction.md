WITH queries are (probably) not supported in the JDBC driver
Cloud Spanner now also supports `WITH` clauses to be added to queries, e.g.:

```sql
WITH subQ1 AS (SELECT SchoolID FROM Roster),
     subQ2 AS (SELECT OpponentID FROM PlayerStats)
SELECT * FROM subQ1
UNION ALL
SELECT * FROM subQ2;
```

These queries will (probably) not be recognized as a `SELECT` query by the JDBC driver.

https://cloud.google.com/spanner/docs/query-syntax#with-clause
