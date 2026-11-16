Implement `tree` explain for `LocalLimitExec`
### Is your feature request related to a problem or challenge?

- Part of https://github.com/apache/datafusion/issues/14914

@irenjj  added a new `tree` explain mode in https://github.com/apache/datafusion/pull/14677. Now we need to add support for different types of operators.

Here is an example of how to see the new explain plans:
```sql
set datafusion.explain.format = 'tree';
create table foo(x int, y int) as values (1,2), (3,4);
explain select * from foo where x = 4;
+---------------+------------------------------------+
| plan_type     | plan                               |
+---------------+------------------------------------+
| logical_plan  | Filter: foo.x = Int32(4)           |
|               |   TableScan: foo projection=[x, y] |
| physical_plan | ┌───────────────────────────┐      |
|               | │    CoalesceBatchesExec    │      |
|               | └─────────────┬─────────────┘      |
|               | ┌─────────────┴─────────────┐      |
|               | │         FilterExec        │      |
|               | └─────────────┬─────────────┘      |
|               | ┌─────────────┴─────────────┐      |
|               | │       DataSourceExec      │      |
|               | │    --------------------   │      |
|               | │    partition_sizes: [1]   │      |
|               | │       partitions: 1       │      |
|               | └───────────────────────────┘      |
|               |                                    |
+---------------+------------------------------------+
```


### Describe the solution you'd like

Add `tree` format to the ExecutionPlan specified in the subject of this ticket

Note that the tree mode should have only the most relevant information for users to understand what plan is being run. Detailed iformation

The process goes like:
1. Add the relevant code to the operator
2. Add / update explain_tree.slt test to show the new code in action

The relevant code looks like this
[HIDDEN]


You can run the tests like
```shell
cargo test --test sqllogictests -- explain_tree
```

You can update the test like this:
```shell
cargo test --test sqllogictests -- explain_tree --complete
```



### Describe alternatives you've considered

Here is an example PR that shows what is needed
- https://github.com/apache/datafusion/pull/15001

### Additional context

Since this is well specified and has several examples and will give exposure to DataFusion code and testing, I have marked this as a good first issue

### Additional contract requirements

- In `tree` explain output, every `LocalLimitExec` node must show concise, non-empty information that tells a user which limit the operator applies, so the operator can be understood from the plan.
