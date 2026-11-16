Why does this fail (is it because of conflict with `interval` as result alias?)
```sql
SELECT
    toStartOfInterval(timestamp, toIntervalMinute(1)) AS interval,
    column_name
FROM table
WHERE true
GROUP BY (interval, column_name)
ORDER BY (interval, column_name) ASC
```

It throws **_line 5:18 unexpected token kind: ,_**
