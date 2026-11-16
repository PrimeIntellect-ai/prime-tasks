Filtering for existing labels being `NULL`
With system-wide profiling in Parca and Parca Agent it might be interesting to once in a while filter for all series that don't have a specific label. Like, "show me all series that don't have a `namespace` label", basically excluding everything that's Kubernetes related.

Here are some examples we should support in FrostDB and add to the [filter](https://github.com/polarsignals/frostdb/blob/main/logictest/testdata/exec/filter/filter) logic test.

```
exec
select labels, stacktrace, timestamp, value where labels.label5 = ''
----
value1  value2  null    null    stack1  1       1
value2  value2  value3  null    stack1  2       2
value3  value2  null    value4  stack1  3       3

exec
select labels, stacktrace, timestamp, value where labels.label4 = null
----
value1  value2  null    null    stack1  1       1
value2  value2  value3  null    stack1  2       2
```

We can debate whether the first one makes sense. However, the concept of `null` isn't really a concept in PromQL and most other languages afaik.
