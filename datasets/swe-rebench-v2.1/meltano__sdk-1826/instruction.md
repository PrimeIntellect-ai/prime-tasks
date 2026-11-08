bug: `Object of type Decimal is not JSON serializable`
### Meltano Version

2.16.0

### Python Version

3.9

### Bug scope

API

### Operating System

macOS - 13.4.1 (22F82)

### Description

Executing a simple sync between a MySQL extractor with `mariadb` engine and Snowflake I eventually get the following error

### Code

```python
> meltano run main target-snowflake

2023-07-10T14:45:18.870028Z [info     ] joblib.externals.loky.process_executor._RemoteTraceback: cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870117Z [info     ] """                            cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870205Z [info     ] Traceback (most recent call last): cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870302Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/_parallel_backends.py", line 273, in _wrap_func_call cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870390Z [info     ]     return func()              cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870481Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 588, in __call__ cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870578Z [info     ]     return [func(*args, **kwargs) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870674Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 588, in <listcomp> cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870778Z [info     ]     return [func(*args, **kwargs) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.870951Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 504, in _drain_sink cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871131Z [info     ]     self.drain_one(sink)       cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871258Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 494, in drain_one cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871412Z [info     ]     sink.process_batch(draining_status) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871533Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/sinks/sql.py", line 267, in process_batch cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871622Z [info     ]     self.bulk_insert_records(  cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871711Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/target_snowflake/sinks.py", line 141, in bulk_insert_records cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871802Z [info     ]     for files in batches:      cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871891Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/batch.py", line 106, in get_batches cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.871981Z [info     ]     gz.writelines(             cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.872074Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/batch.py", line 107, in <genexpr> cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.872168Z [info     ]     (json.dumps(record) + "\n").encode() for record in chunk cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.872269Z [info     ]   File "/Users/dimos/.pyenv/versions/3.9.12/lib/python3.9/json/__init__.py", line 231, in dumps cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.872382Z [info     ]     return _default_encoder.encode(obj) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.872495Z [info     ]   File "/Users/dimos/.pyenv/versions/3.9.12/lib/python3.9/json/encoder.py", line 199, in encode cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.872599Z [info     ]     chunks = self.iterencode(o, _one_shot=True) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.873641Z [info     ]   File "/Users/dimos/.pyenv/versions/3.9.12/lib/python3.9/json/encoder.py", line 257, in iterencode cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.873927Z [info     ]     return _iterencode(o, 0)   cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874108Z [info     ]   File "/Users/dimos/.pyenv/versions/3.9.12/lib/python3.9/json/encoder.py", line 179, in default cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874214Z [info     ]     raise TypeError(f'Object of type {o.__class__.__name__} ' cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874310Z [info     ] TypeError: Object of type Decimal is not JSON serializable cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874414Z [info     ] """                            cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874550Z [info     ]                                cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874700Z [info     ] The above exception was the direct cause of the following exception: cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.874956Z [info     ]                                cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875198Z [info     ] Traceback (most recent call last): cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875357Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/bin/target-snowflake", line 8, in <module> cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875450Z [info     ]     sys.exit(TargetSnowflake.cli()) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875536Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/click/core.py", line 1157, in __call__ cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875620Z [info     ]     return self.main(*args, **kwargs) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875704Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/click/core.py", line 1078, in main cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875787Z [info     ]     rv = self.invoke(ctx)      cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875870Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/click/core.py", line 1434, in invoke cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.875954Z [info     ]     return ctx.invoke(self.callback, **ctx.params) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.876038Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/click/core.py", line 783, in invoke cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.876121Z [info     ]     return __callback(*args, **kwargs) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.876376Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 549, in invoke cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.876615Z [info     ]     target.listen(file_input)  cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.876831Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/io_base.py", line 34, in listen cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.876946Z [info     ]     self._process_lines(file_input) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877039Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 291, in _process_lines cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877131Z [info     ]     counter = super()._process_lines(file_input) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877219Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/io_base.py", line 93, in _process_lines cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877307Z [info     ]     self._process_record_message(line_dict) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877402Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 355, in _process_record_message cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877493Z [info     ]     self._handle_max_record_age() cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877585Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 279, in _handle_max_record_age cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877674Z [info     ]     self.drain_all()           cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877760Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 474, in drain_all cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877849Z [info     ]     self._drain_all(list(self._sinks_active.values()), self.max_parallelism) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.877937Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/singer_sdk/target_base.py", line 507, in _drain_all cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878026Z [info     ]     Parallel()(delayed(_drain_sink)(sink=sink) for sink in sink_list) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878119Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 1944, in __call__ cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878214Z [info     ]     return output if self.return_generator else list(output) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878309Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 1587, in _get_outputs cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878544Z [info     ]     yield from self._retrieve() cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878677Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 1691, in _retrieve cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878782Z [info     ]     self._raise_error_fast()   cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878878Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 1726, in _raise_error_fast cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.878969Z [info     ]     error_job.get_result(self.timeout) cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.879058Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 735, in get_result cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.879149Z [info     ]     return self._return_or_raise() cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.879241Z [info     ]   File "/Users/dimos/repos/data/super-mario/data/extract-load/meltano/.meltano/loaders/target-snowflake/venv/lib/python3.9/site-packages/joblib/parallel.py", line 753, in _return_or_raise cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.879329Z [info     ]     raise self._result         cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:18.879419Z [info     ] TypeError: Object of type Decimal is not JSON serializable cmd_type=elb consumer=True name=target-snowflake producer=False stdio=stderr string_id=target-snowflake
2023-07-10T14:45:19.673299Z [error    ] Loader failed
2023-07-10T14:45:19.678282Z [error    ] Block run completed.           block_type=ExtractLoadBlocks err=RunnerError('Loader failed') exit_codes={<PluginType.LOADERS: 'loaders'>: 1} set_number=0 success=False
```
