IN clause does not allow date literals
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description

The following query is valid but throws an exception while being parsed:

```sql
SELECT Id
FROM Account
WHERE CreatedDate IN (TODAY, THIS_MONTH)
```

### Additional contract requirements

- A `WHERE` clause whose `IN` set contains date literals (for example `WHERE CreatedDate IN (TODAY, THIS_MONTH)`) is valid and parses successfully.
- The parsed `Condition` (the `left` side of a parsed `WHERE` clause returned by `parseQuery`) exposes the set elements through `value`, and exposes `dateLiteralVariable?: number | number[]` populated with the numeric value(s) of any variable date literals (for example `LAST_N_DAYS:4`) present in the set.
