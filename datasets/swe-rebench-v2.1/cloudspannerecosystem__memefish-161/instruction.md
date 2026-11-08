Support ALTER DATABASE statement
`ALTER DATABASE` statement is not yet supported.

https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#alter-database

```
ALTER DATABASE database_id
    action

where database_id is:
    {a—z}[{a—z|0—9|_|-}+]{a—z|0—9}

and action is:
    SET OPTIONS ( options_def [, ... ] )

and options_def is:
    { default_leader = { 'region' | null } |
      optimizer_version = { 1 ... 7 | null } |
      optimizer_statistics_package = { 'package_name' | null } |
      version_retention_period = { 'duration' | null } }
```

Related

- #115

### Additional contract requirements

- The `SET OPTIONS` action must also accept the option name `enable_key_visualizer`
  with a boolean value (`true` or `false`).
- Each option value listed above may also be given as the literal `null`.
