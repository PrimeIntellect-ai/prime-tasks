Current aggregation functions are case-sensitive
```sql
SELECT COUNT(*) FROM TableA;

SELECT count(*) FROM TableA;
```

both should work but the second one is not working.
