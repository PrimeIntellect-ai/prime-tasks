SQL Magic %%sql drops column if first row value is null/NaN
It seems that the dataframe visualization for an SQL query will exclude a column outright if the first row contains a `NULL` or `NaN` value for that column.

Consider this example, where the only difference between the queries is the `ORDER` of the results.
![image](https://cloud.githubusercontent.com/assets/8999918/25245572/7d32f8a6-25ca-11e7-8862-351f3d74480d.png)

## Observed with
notebook 4.4.1
sparkmagic 0.11.1
kernel PySpark

## Courtesy Text for Copy/Paste:
```
%%sql
select * from (
  select 1 as foo, 2 as bar
  union all
  select 3, NULL
) x
order by bar asc
```

### Additional contract requirements

- When records contain the keys `z`, `nullv`, and `y`, the resulting dataframe must order its columns as `z`, `nullv`, `y`, including when the first record omits `nullv`.
