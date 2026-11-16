NULL is not sorted first when using ORDER BY
Table example:

```sql
BEGIN TRANSACTION;
CREATE TABLE players (...);
INSERT INTO players VALUES {"name": "Rafael Nadal", "age": 36, "nationality": "Spain", "career": {"australia": 2, "france": 14, "wimbledon": 2, "us": 4}, "coach": ["Francisco Roig", "Carlos Moyá", "Marc López"]};
INSERT INTO players VALUES {"name": "Roger Federer", "age": 40, "nationality": "Switzerland", "career": {"australia": 6, "france": 1, "wimbledon": 8, "us": 5}, "coach": ["Ivan Ljubičić", "Severin Lüthi"]};
INSERT INTO players VALUES {"name": "Andrew Barron Murray", "coach": ["Ivan Lendl"]};
COMMIT;
```

Query:

```sql
genji> SELECT name, career.australia AS australia FROM players ORDER BY career.australia;
{
  "name": "Rafael Nadal",
  "australia": 2
}
{
  "name": "Roger Federer",
  "australia": 6
}
{
  "name": "Andrew Barron Murray",
  "australia": null
}
```

The last document should be first

### Additional contract requirements

- For descending ORDER BY, rows with NULL sort-key values must appear after rows with non-NULL sort-key values.
