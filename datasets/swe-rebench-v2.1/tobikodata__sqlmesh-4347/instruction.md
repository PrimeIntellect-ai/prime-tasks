bug: table_diff fails with a pydantic error
```
demo.incremental_model ...

Table diff failed!
Error: 10 validation errors for RowDiff
stats.s_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.t_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.join_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.null_grain_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.full_match_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.id_matches
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.item_id_matches
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.event_date_matches
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.s_only_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
stats.t_only_count
  Input should be a valid number [type=float_type, input_value=None, input_type=NoneType]
    For further information visit https://errors.pydantic.dev/2.11/v/float_type
(.venv) ➜  sqlmesh-demos git:(sung/vscode) ✗
```

Model that's diffed.
```
MODEL (
  name demo.incremental_model_new,
  kind INCREMENTAL_BY_TIME_RANGE (
    time_column event_date
  ),
  start '2020-01-01',
  cron '@daily',
  grain (id, event_date),
  stamp 'fix hydration issue',
  owner 'sung'
);

SELECT
  id,
  item_id,
  event_date,
  '1' AS new_column
FROM demo.seed_model
WHERE
  event_date BETWEEN @start_date AND @end_date
```
