Macros can consume too much of a query containing parentheses
<!--
Please use this template while reporting a bug and provide as much info as possible.
Questions should be posted to https://community.grafana.com
-->

**What happens**:
When queries containing parentheses are parsed, sometimes the macro args consume too much of the query string. This was partially addressed in sqlds with https://github.com/grafana/sqlds/issues/82, but it affects other characters besides strings. For example, with a macro like

```sql
select * from foo where $__num*(table.a + table.b) > 1000000 limit 100",
```

the parser will consider `*(table.a + table.b)` as an argument list to the `num` macro, so that if `num` returns 10000, for example, sometimes the interpolated query will be:

```sql
select * from foo where 10000 > 1000000 limit 100",
```

**What you expected to happen**:
Parenthesized subexpressions of queries should only be taken as macro args if the parenthesis immediately follows the macro name.

**How to reproduce it (as minimally and precisely as possible)**:
See the unit test added [here](https://github.com/grafana/grafana-plugin-sdk-go/blob/a9a867125d5c179b29fc128b46cd6f2e6bb293b9/data/sqlutil/macros_test.go#L178), which fails (intermittently) with the current code here and with the code in `sqlds/macros.go`.
