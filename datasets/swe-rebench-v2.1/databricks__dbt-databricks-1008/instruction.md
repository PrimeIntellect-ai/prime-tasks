dbt compilation error with not_null model constraint
### Describe the bug
We’ve encountered an issue with model constraints that include more than one column that got introduced in 1.10.0, see [(876)](https://github.com/databricks/dbt-databricks/pull/876).

### Steps To Reproduce
When building a model with a model constraint of type `not_null` for two columns `col1` and `col2` it fails with a compilation error:

```
Compilation Error in model example_model (models/example_model.sql)
  set.add() takes exactly one argument (2 given)

  > in macro materialization_table_databricks (macros/materializations/table.sql)
  > called by model example_model (models/example_model.sql)
```

### Expected behavior
Building a model with model constraints that include multiple columns should work as it does in previous versions.

### Screenshots and log output
```
Compilation Error in model example_model (models/example_model.sql)
  set.add() takes exactly one argument (2 given)

  > in macro materialization_table_databricks (macros/materializations/table.sql)
  > called by model example_model (models/example_model.sql)
```

### System information
**The output of `dbt --version`:**
```
1.10.0
```

**The operating system you're using:**
Ubuntu 22.04.5 LTS

**The output of `python --version`:**
3.11.11

### Additional context
[Link to the code](https://github.com/databricks/dbt-databricks/blob/4b5dcc534c74eba55ca75976277a82b94f5531ee/dbt/adapters/databricks/constraints.py#L206)

[HIDDEN]
