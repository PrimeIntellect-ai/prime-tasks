information_schema.columns data_type has uppercase values
I was trying to use the Grafana MySQL data source with this library, and it makes the following query to get autocomplete results for a column dropdown:

```
SELECT column_name FROM information_schema.columns WHERE table_schema = database() AND table_name = 'mytable' AND data_type IN ('timestamp','datetime','bigint','int','double','float') ORDER BY column_name
```

This works on real MySQL servers (at least the one I tested), but returns no results for the information_schema database provided by this library. I believe the reason is that the information_schema from this library uses uppercase values for the data_type column (e.g 'DOUBLE', 'BIGINT', etc.), so no results come back. Would it make sense to make the values in this column lowercase?
