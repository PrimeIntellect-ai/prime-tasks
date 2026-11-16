`INTERVAL` does not allow for sign (+/-) before the literal
## Description
- `INTERVAL` literals do not allow for a sign before the interval value
- Parsing is fine but bug is in the AST -> Plan conversion

## To Reproduce
```
partiql ▶ INTERVAL '-10' YEAR (2);
e: [semantic] Unexpected failure encountered. Caused by: java.lang.IllegalStateException: Invalid interval string: '-10'.
java.lang.IllegalStateException: Invalid interval string: '-10'
        at org.partiql.planner.internal.util.IntervalUtils.parseIntervalSingle(IntervalUtils.kt:48)
        at org.partiql.planner.internal.util.IntervalUtils.parseInterval$partiql_planner(IntervalUtils.kt:21)
```

## Expected Behavior
Expect to be able to parse negative interval literal values/.

## Additional Context
- Java version: 17
- PartiQL version: 1.2.3-SNAPSHOT
