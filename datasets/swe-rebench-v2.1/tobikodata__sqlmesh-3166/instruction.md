SQLMesh fails to create a materialized views in BigQuery when registering comments
When using a materialized view that has comments, its creation succeeds in BQ, but later fails with the following trace:

```
2024-09-23 16:34:22,095 - MainThread - sqlmesh.core.context - ERROR - Apply Failure: Traceback (most recent call last):
  File ".venv/lib/python3.11/site-packages/sqlmesh/utils/concurrency.py", line 69, in _process_node
    self.fn(node)
  File ".venv/lib/python3.11/site-packages/sqlmesh/utils/concurrency.py", line 165, in <lambda>
    lambda s_id: fn(snapshots_by_id[s_id]),
                 ^^^^^^^^^^^^^^^^^^^^^^^^^
  File ".venv/lib/python3.11/site-packages/sqlmesh/core/snapshot/evaluator.py", line 300, in <lambda>
    lambda s: self._create_snapshot(
              ^^^^^^^^^^^^^^^^^^^^^^
  File ".venv/lib/python3.11/site-packages/sqlmesh/core/snapshot/evaluator.py", line 708, in _create_snapshot
    evaluation_strategy.create(
  File ".venv/lib/python3.11/site-packages/sqlmesh/core/snapshot/evaluator.py", line 1604, in create
    self.adapter.create_view(
  File ".venv/lib/python3.11/site-packages/sqlmesh/core/engine_adapter/shared.py", line 290, in internal_wrapper
    return func(*list_args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  [HIDDEN]
  File ".venv/lib/python3.11/site-packages/sqlmesh/core/engine_adapter/bigquery.py", line 711, in _db_call
    return func(
           ^^^^^
  File ".venv/lib/python3.11/site-packages/google/cloud/bigquery/client.py", line 1431, in update_table
    api_response = self._call_api(
                   ^^^^^^^^^^^^^^^
  File ".venv/lib/python3.11/site-packages/google/cloud/bigquery/client.py", line 833, in _call_api
    return call()
           ^^^^^^
  File ".venv/lib/python3.11/site-packages/google/api_core/retry/retry_unary.py", line 293, in retry_wrapped_func
    return retry_target(
           ^^^^^^^^^^^^^
  File ".venv/lib/python3.11/site-packages/google/api_core/retry/retry_unary.py", line 153, in retry_target
    _retry_error_helper(
  File ".venv/lib/python3.11/site-packages/google/api_core/retry/retry_base.py", line 212, in _retry_error_helper
    raise final_exc from source_exc
  File ".venv/lib/python3.11/site-packages/google/api_core/retry/retry_unary.py", line 144, in retry_target
    result = target()
             ^^^^^^^^
  File ".venv/lib/python3.11/site-packages/google/cloud/_http/__init__.py", line 494, in api_request
    raise exceptions.from_http_response(response)
google.api_core.exceptions.BadRequest: 400 PATCH https://bigquery.googleapis.com/bigquery/v2/projects/<redacted>/datasets/<redacted>/tables/<redacted>?prettyPrint=false: Schema update for materialized views is not supported.
```

Using `v0.123.3`
