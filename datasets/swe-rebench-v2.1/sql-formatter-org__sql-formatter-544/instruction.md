Feature Request: Place `ON CONFLICT` on new line
**Describe the Feature**
Place `ON CONFLICT` on new line.

Current behaviour:
```sql
INSERT INTO
    tests (val)
VALUES
    (1),
    (2) ON CONFLICT (val)
DO NOTHING;
```

Wanted behaviour:
```sql
INSERT INTO
    tests (val)
VALUES
    (1),
    (2)
ON CONFLICT (val)
DO NOTHING;
```

### Additional contract requirements

- For PostgreSQL and SQLite, formatting `INSERT INTO tbl VALUES (1,'Blah') ON CONFLICT DO NOTHING;` must produce:
```sql
INSERT INTO
  tbl
VALUES
  (1, 'Blah')
ON CONFLICT DO NOTHING;
```
- For PostgreSQL and SQLite, formatting `INSERT INTO tests (val) VALUES (1), (2) ON CONFLICT (val) DO NOTHING;` must place `ON CONFLICT (val)` on a new line after the `VALUES` list.
