error when validating if a table exists
I found an error when validating if a table exists, because it doesn't check if a CTE has been stored:

```sql
%%sql --save many_passengers --no-execute
SELECT *
FROM taxi
WHERE passenger_count > 3
-- remove top 1% outliers for better visualization
AND trip_distance < 18.93
```

Then, using:

```sql
%sqlplot histogram --table many_passengers --column trip_distance --with many_passengers
```

Throws this error:

```
ValueError: There is no table with name 'many_passengers' in the default schema
If you need help solving this issue, send us a message: https://ploomber.io/community
```

Even though I already stored `many_passengers` using `--save`


Note: this is blocking the release

cc @idomic @yafimvo

### Additional contract requirements

- When `%sqlcmd columns`, `%sqlcmd profile`, `%sqlplot histogram`, or `%sqlplot boxplot` uses `--table` to name a saved query but omits `--with`, raise a `ValueError` whose message includes `but there is a stored query.\nDid you miss passing --with {table}?`, replacing `{table}` with the saved query name.
- When `%sqlplot histogram` or `%sqlplot boxplot` is given a saved query via `--table` together with `--with`, table validation must not raise the "no table" error, even when the saved query cannot be executed against the database.
