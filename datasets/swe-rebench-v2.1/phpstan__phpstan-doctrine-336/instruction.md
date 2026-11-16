`CASE WHEN EXISTS(...) THEN TRUE ELSE FALSE END AS my_column` is not inferred as boolean
- Create an ORM QueryBuilder
- Call `->select('CASE WHEN EXISTS(SELECT 1) THEN TRUE ELSE FALSE END AS my_column')`
- Call `->getQuery()->getResult()`

See the type of `my_column` inferred as `0|'0'`
