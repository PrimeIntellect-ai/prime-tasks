[ADAP-834] [Regression] `adapter.is_replacable()` always evaluates to `False` with dbt-bigquery 1.6
### Is this a new bug in dbt-bigquery?

- [X] I believe this is a new bug in dbt-bigquery
- [X] I have searched the existing issues, and I could not find an existing issue for this bug

### Current Behavior

There's a pretty strange behaviour with 1.6 where the `adapter.is_replacable()` method seems to always evaluate to `False` in 1.6, even if the partition configuration of a model has not been changed. This could cause unintended side-effects - like dropping the previous table even if not required.

https://github.com/dbt-labs/dbt-bigquery/blob/eb58c7db58d389695f6f2dad8b4f4c8f5f4b5db3/dbt/include/bigquery/macros/materializations/table.sql#L27-L30

### Expected Behavior

We should keep to the behaviour prior to 1.6.

### Steps To Reproduce

1. Create a random table in BQ:

```sql
create or replace table sources.raw as (
  select cast(1 as int64) as id, parse_date('%Y-%m-%d', '1970-01-01') as updated_at, parse_date('%Y-%m-%d', '1970-01-01') as updated_at_utc
);
```

2. Use that in our dbt project/model:

```yaml
# dbt_project.yml
name: my_dbt_project
profile: bigquery
config-version: 2
version: 1.0

models:
  my_dbt_project:
    +materialized: table
```

```sql
-- models/foo.sql
{{
  config(
    partition_by={
      "field": "updated_at",
      "data_type": "date",
    }
  )
}}

select id, updated_at, updated_at_utc from sources.raw
```

3. Run model `foo` a few times:

```sh
$ dbt --debug run -s foo | grep 'Hard refreshing'
03:25:04  Hard refreshing `cse-sandbox-319708`.`dbt_jyeo`.`foo` because it is not replaceable

$ dbt --debug run -s foo | grep 'Hard refreshing'
03:26:32  Hard refreshing `cse-sandbox-319708`.`dbt_jyeo`.`foo` because it is not replaceable

$ dbt --debug run -s foo | grep 'Hard refreshing'
03:27:53  Hard refreshing `cse-sandbox-319708`.`dbt_jyeo`.`foo` because it is not replaceable
```

Attached a full debug log for one of the above invocations - but nothing of interest really.

If you downgrade to dbt-bigquery 1.5.latest (`dbt==1.5.4, dbt-bigquery==1.5.5`) - you will not see such log lines.

### Relevant log output

```shell
============================== 15:26:43.235266 | ca188e3e-6302-4f60-ad5d-169c9307ed49 ==============================
[0m15:26:43.235266 [info ] [MainThread]: Running with dbt=1.6.0
[0m15:26:43.238415 [debug] [MainThread]: running dbt with arguments {'printer_width': '80', 'indirect_selection': 'eager', 'log_cache_events': 'False', 'write_json': 'True', 'partial_parse': 'False', 'cache_selected_only': 'False', 'warn_error': 'None', 'fail_fast': 'False', 'profiles_dir': '/Users/jeremy/.dbt', 'log_path': '/Users/jeremy/src/dbt-basic/logs', 'version_check': 'True', 'debug': 'True', 'use_colors': 'True', 'use_experimental_parser': 'False', 'no_print': 'None', 'quiet': 'False', 'warn_error_options': 'WarnErrorOptions(include=[], exclude=[])', 'invocation_command': 'dbt --debug run -s foo', 'static_parser': 'True', 'introspect': 'True', 'target_path': 'None', 'log_format': 'default', 'send_anonymous_usage_stats': 'True'}
[0m15:26:43.658536 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'project_id', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x1149e6490>]}
[0m15:26:43.670146 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'adapter_info', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x114a08fd0>]}
[0m15:26:43.671030 [info ] [MainThread]: Registered adapter: bigquery=1.6.1
[0m15:26:43.690171 [debug] [MainThread]: checksum: 08dabea3fc65f9f8dd48613681c2bcd827397a7ba9ce4c6d52980aba1215e8c9, vars: {}, profile: , target: , version: 1.6.0
[0m15:26:43.691439 [debug] [MainThread]: Partial parsing not enabled
[0m15:26:44.679029 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'load_project', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x114bc0f40>]}
[0m15:26:44.690776 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'resource_counts', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x114c013a0>]}
[0m15:26:44.691499 [info ] [MainThread]: Found 1 model, 0 sources, 0 exposures, 0 metrics, 393 macros, 0 groups, 0 semantic models
[0m15:26:44.691998 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'runnable_timing', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x114c01d00>]}
[0m15:26:44.693343 [info ] [MainThread]:
[0m15:26:44.694420 [debug] [MainThread]: Acquiring new bigquery connection 'master'
[0m15:26:44.695676 [debug] [ThreadPool]: Acquiring new bigquery connection 'list_cse-sandbox-319708'
[0m15:26:44.696432 [debug] [ThreadPool]: Opening a new connection, currently in state init
[0m15:26:47.381186 [debug] [ThreadPool]: Re-using an available connection from the pool (formerly list_cse-sandbox-319708, now list_cse-sandbox-319708_dbt_jyeo)
[0m15:26:47.383105 [debug] [ThreadPool]: Opening a new connection, currently in state closed
[0m15:27:51.026784 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'runnable_timing', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x114c01520>]}
[0m15:27:51.029280 [info ] [MainThread]: Concurrency: 1 threads (target='dev')
[0m15:27:51.030325 [info ] [MainThread]:
[0m15:27:51.034065 [debug] [Thread-1  ]: Began running node model.my_dbt_project.foo
[0m15:27:51.035037 [info ] [Thread-1  ]: 1 of 1 START sql table model dbt_jyeo.foo ...................................... [RUN]
[0m15:27:51.036023 [debug] [Thread-1  ]: Re-using an available connection from the pool (formerly list_cse-sandbox-319708_dbt_jyeo, now model.my_dbt_project.foo)
[0m15:27:51.036645 [debug] [Thread-1  ]: Began compiling node model.my_dbt_project.foo
[0m15:27:51.049778 [debug] [Thread-1  ]: Writing injected SQL for node "model.my_dbt_project.foo"
[0m15:27:51.051744 [debug] [Thread-1  ]: Timing info for model.my_dbt_project.foo (compile): 15:27:51.037414 => 15:27:51.051291
[0m15:27:51.052729 [debug] [Thread-1  ]: Began executing node model.my_dbt_project.foo
[0m15:27:51.385636 [debug] [Thread-1  ]: Opening a new connection, currently in state closed
[0m15:27:53.573190 [debug] [Thread-1  ]: Hard refreshing `cse-sandbox-319708`.`dbt_jyeo`.`foo` because it is not replaceable
[0m15:27:54.042441 [debug] [Thread-1  ]: Writing runtime sql for node "model.my_dbt_project.foo"
[0m15:27:54.043663 [debug] [Thread-1  ]: On model.my_dbt_project.foo: /* {"app": "dbt", "dbt_version": "1.6.0", "profile_name": "bigquery", "target_name": "dev", "node_id": "model.my_dbt_project.foo"} */




    create or replace table `cse-sandbox-319708`.`dbt_jyeo`.`foo`

    partition by updated_at


    OPTIONS()
    as (


select id, updated_at, updated_at_utc from sources.raw
    );

[0m15:27:54.686915 [debug] [Thread-1  ]: BigQuery adapter: https://console.cloud.google.com/bigquery?project=cse-sandbox-319708&j=bq:US:4fd0985b-13ae-4a99-8031-a01660c1309c&page=queryresults
[0m15:27:57.316830 [debug] [Thread-1  ]: Timing info for model.my_dbt_project.foo (execute): 15:27:51.053306 => 15:27:57.316518
[0m15:27:57.318224 [debug] [Thread-1  ]: Sending event: {'category': 'dbt', 'action': 'run_model', 'label': 'ca188e3e-6302-4f60-ad5d-169c9307ed49', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x11dfa7310>]}
[0m15:27:57.319347 [info ] [Thread-1  ]: 1 of 1 OK created sql table model dbt_jyeo.foo ................................. [[32mCREATE TABLE (1.0 rows, 24.0 Bytes processed)[0m in 6.28s]
[0m15:27:57.320263 [debug] [Thread-1  ]: Finished running node model.my_dbt_project.foo
[0m15:27:57.323528 [debug] [MainThread]: Connection 'master' was properly closed.
[0m15:27:57.324211 [debug] [MainThread]: Connection 'model.my_dbt_project.foo' was properly closed.
[0m15:27:57.324755 [info ] [MainThread]:
[0m15:27:57.325270 [info ] [MainThread]: Finished running 1 table model in 0 hours 1 minutes and 12.63 seconds (72.63s).
[0m15:27:57.326546 [debug] [MainThread]: Command end result
[0m15:27:57.337341 [info ] [MainThread]:
[0m15:27:57.338012 [info ] [MainThread]: [32mCompleted successfully[0m
[0m15:27:57.338515 [info ] [MainThread]:
[0m15:27:57.339076 [info ] [MainThread]: Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
[0m15:27:57.339913 [debug] [MainThread]: Command `dbt run` succeeded at 15:27:57.339797 after 74.14 seconds
[0m15:27:57.340449 [debug] [MainThread]: Sending event: {'category': 'dbt', 'action': 'invocation', 'label': 'end', 'context': [<snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x110808040>, <snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x114badf10>, <snowplow_tracker.self_describing_json.SelfDescribingJson object at 0x1149f0670>]}
[0m15:27:57.340996 [debug] [MainThread]: Flushing usage events
```


### Environment

```markdown
- OS: macOS
- Python: Python 3.9.13
- dbt-core: 1.6.0
- dbt-bigquery: 1.6.1
```


### Additional Context

To confirm `is_replacable` is evaluating incorrectly with 1.6, I used a custom materialization next:

```jinja
{%- materialization m8n, default -%}

  {%- set identifier = model['alias'] -%}
  {%- set old_relation = adapter.get_relation(database=database, schema=schema, identifier=identifier) -%}
  {%- set target_relation = api.Relation.create(database=database, schema=schema, identifier=identifier, type='table') -%}

  {%- set raw_partition_by = config.get('partition_by', none) -%}
  {%- set partition_by = adapter.parse_partition_by(raw_partition_by) -%}
  {%- set cluster_by = config.get('cluster_by', none) -%}

  {%- do log('>>>>> is_replacable evaluated to: ' ~ adapter.is_replaceable(old_relation, partition_by, cluster_by), True) -%}

  {% call statement('main') -%}
    {{ create_table_as(False, target_relation, compiled_code, 'sql') }}
  {%- endcall %}

  {{ return({'relations': [target_relation]}) }}

{%- endmaterialization -%}
```

Then modify `foo.sql` to make use of it:

```sql
-- models/foo.sql
{{
  config(
    materialized = 'm8n',
    partition_by={
      "field": "updated_at",
      "data_type": "date",
    }
  )
}}

select id, updated_at, updated_at_utc from sources.raw
```

```sh
(venv_dbt_1.6.latest) ➜  dbt-basic git:(main) ✗ dbt run -s foo
03:35:16  Running with dbt=1.6.0
03:35:17  Registered adapter: bigquery=1.6.1
03:35:18  Found 1 model, 0 sources, 0 exposures, 0 metrics, 393 macros, 0 groups, 0 semantic models
03:35:18
03:36:32  Concurrency: 1 threads (target='dev')
03:36:32
03:36:32  1 of 1 START sql m8n model dbt_jyeo.foo ........................................ [RUN]
03:36:34  >>>>> is_replacable evaluated to: False
03:36:38  1 of 1 OK created sql m8n model dbt_jyeo.foo ................................... [CREATE TABLE (1.0 rows, 24.0 Bytes processed) in 5.98s]
03:36:38
03:36:38  Finished running 1 m8n model in 0 hours 1 minutes and 19.97 seconds (79.97s).
03:36:38
03:36:38  Completed successfully
03:36:38
03:36:38  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
(venv_dbt_1.6.latest) ➜  dbt-basic git:(main) ✗ deactivate
➜  dbt-basic git:(main) ✗ source venv_dbt_1.5.latest/bin/activate
(venv_dbt_1.5.latest) ➜  dbt-basic git:(main) ✗ dbt run -s foo
03:36:55  Running with dbt=1.5.4
03:36:56  Registered adapter: bigquery=1.5.5
03:36:56  Found 1 model, 0 tests, 0 snapshots, 0 analyses, 360 macros, 0 operations, 0 seed files, 0 sources, 0 exposures, 0 metrics, 0 groups
03:36:56
03:38:06  Concurrency: 1 threads (target='dev')
03:38:06
03:38:06  1 of 1 START sql m8n model dbt_jyeo.foo ........................................ [RUN]
03:38:08  >>>>> is_replacable evaluated to: True
03:38:12  1 of 1 OK created sql m8n model dbt_jyeo.foo ................................... [CREATE TABLE (1.0 rows, 24.0 Bytes processed) in 5.73s]
03:38:12
03:38:12  Finished running 1 m8n model in 0 hours 1 minutes and 15.13 seconds (75.13s).
03:38:12
03:38:12  Completed successfully
03:38:12
03:38:12  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
```

### Additional contract requirements

- `PartitionConfig` must be importable from the `dbt.adapters.bigquery` package, i.e. `from dbt.adapters.bigquery import PartitionConfig`.
- `PartitionConfig.parse(data)` in `dbt.adapters.bigquery.impl` accepts a mapping of partition configuration keys (`field`, `data_type`, `granularity`, `range`, `time_ingestion_partitioning`, `copy_partitions`) and returns a `PartitionConfig`. It raises a validation error when a supplied value has an invalid type.
- `BigQueryAdapter._partitions_match(table, partition_config)` in `dbt.adapters.bigquery.impl` returns `True` when the table's partitioning matches the supplied `PartitionConfig`, and `False` otherwise. Field names and granularity are compared case-insensitively, and both time partitioning and range partitioning are handled.
- `BigQueryAdapter.is_replaceable(relation, partition_config, cluster_config)` returns `True` when the existing table's partitioning and clustering match the supplied configuration, so that a model whose partition configuration has not changed remains replaceable.
