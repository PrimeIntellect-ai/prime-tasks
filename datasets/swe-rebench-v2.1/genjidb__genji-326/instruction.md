COUNT(*) with empty set returns nothing
For example, using genji CLI you can reproduce this behavior in the following way:

```sql
CREATE TABLE foo;
SELECT COUNT(*) FROM foo;
```
And it returns literally nothing.

Contrary, if you insert something in table, then you will get proper count of items:

```sql
CREATE TABLE bar;
INSERT INTO bar VALUES {"bar":true};
SELECT COUNT(*) FROM bar;
```

Prints:

```json
{
  "COUNT(*)": 1
}
```

I expect that `SELECT COUNT(*)` for `foo` should return:

```json
{
  "COUNT(*)": 0
}
```

UPD:

I digged code a little bit. The reason (as I understand) is how the aggregates created in [HIDDEN].
If there are no documents in stream then [HIDDEN]

### Additional contract requirements

- For an empty table, `SELECT MAX(a), MIN(b), COUNT(*), SUM(id) FROM test` should return `{"MAX(a)": null, "MIN(b)": null, "COUNT(*)": 0, "SUM(id)": null}`.
