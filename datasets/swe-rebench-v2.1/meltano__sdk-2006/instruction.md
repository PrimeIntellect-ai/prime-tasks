bug: mapper built on SDK errors with `AttributeError: 'str' object has no attribute 'tzinfo`
### Singer SDK Version

0.30.0

### Is this a regression?

- [ ] Yes

### Python Version

NA

### Bug scope

Mapping (stream maps, flattening, etc.)

### Operating System

macOS 12.6, Python 3.11

### Description

I scaffolded a new mapper project from the SDK using `cookiecutter https://github.com/meltano/sdk --directory="cookiecutter/mapper-template"`. I am now trying to test the default behavior (that is, not actually changing any data yet).

I have a few records in a CSV and am testing with `meltano run tap-csv test-decrypt target-jsonl` (where `test-decrypt` is a mapping using my mapper plugin)

I'm getting the following error:

```
$ meltano run tap-csv test-decrypt target-jsonl > out.txt
2023-08-08T16:34:01.331213Z [info     ] Environment 'test' is active
2023-08-08T16:34:04.147620Z [info     ] 2023-08-08 11:34:04,147 | INFO     | tap-csv              | Beginning full_table sync of 'records'... cmd_type=elb consumer=False name=tap-csv producer=True stdio=stderr string_id=tap-csv
2023-08-08T16:34:04.148384Z [info     ] 2023-08-08 11:34:04,147 | INFO     | tap-csv              | Tap has custom mapper. Using 1 provided map(s). cmd_type=elb consumer=False name=tap-csv producer=True stdio=stderr string_id=tap-csv
2023-08-08T16:34:04.150451Z [info     ] 2023-08-08 11:34:04,150 | INFO     | singer_sdk.metrics   | METRIC: {"type": "timer", "metric": "sync_duration", "value": 0.002245187759399414, "tags": {"stream": "records", "context": {}, "status": "succeeded"}} cmd_type=elb consumer=False name=tap-csv producer=True stdio=stderr string_id=tap-csv
2023-08-08T16:34:04.150825Z [info     ] 2023-08-08 11:34:04,150 | INFO     | singer_sdk.metrics   | METRIC: {"type": "counter", "metric": "record_count", "value": 4, "tags": {"stream": "records", "context": {}}} cmd_type=elb consumer=False name=tap-csv producer=True stdio=stderr string_id=tap-csv
2023-08-08T16:34:04.241283Z [info     ] Traceback (most recent call last): cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.241530Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/bin/mapper-my-test-mapper", line 8, in <module> cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.241804Z [info     ]     sys.exit(PawEltDecrypterMapper.cli()) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.241972Z [info     ]              ^^^^^^^^^^^^^^^^^^^^^^^^^^^ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.242135Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/click/core.py", line 1157, in __call__ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.242291Z [info     ]     return self.main(*args, **kwargs) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.242466Z [info     ]            ^^^^^^^^^^^^^^^^^^^^^^^^^^ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.242797Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/click/core.py", line 1078, in main cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243029Z [info     ]     rv = self.invoke(ctx)      cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243185Z [info     ]          ^^^^^^^^^^^^^^^^      cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243332Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/click/core.py", line 1434, in invoke cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243480Z [info     ]     return ctx.invoke(self.callback, **ctx.params) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243641Z [info     ]            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243801Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/click/core.py", line 783, in invoke cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.243967Z [info     ]     return __callback(*args, **kwargs) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.244111Z [info     ]            ^^^^^^^^^^^^^^^^^^^^^^^^^^^ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.244253Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/mapper_base.py", line 134, in invoke cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.244399Z [info     ]     mapper.listen(file_input)  cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.244536Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/io_base.py", line 34, in listen cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.244782Z [info     ]     self._process_lines(file_input) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.244974Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/io_base.py", line 93, in _process_lines cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245129Z [info     ]     self._process_record_message(line_dict) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245277Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/mapper_base.py", line 40, in _process_record_message cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245421Z [info     ]     self._write_messages(self.map_record_message(message_dict)) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245561Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/mapper_base.py", line 33, in _write_messages cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245701Z [info     ]     for message in messages:   cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245843Z [info     ]   File "/Users/matt/dev/my-test-mapper/my_test_mapper/mapper.py", line 73, in map_record_message cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.245983Z [info     ]     yield singer.RecordMessage.from_dict(message_dict) cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246124Z [info     ]           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246261Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/_singerlib/messages.py", line 68, in from_dict cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246401Z [info     ]     return cls(**data)         cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246538Z [info     ]            ^^^^^^^^^^^         cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246695Z [info     ]   File "<string>", line 7, in __init__ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246834Z [info     ]   File "/Users/matt/dev/my-test-mapper/.meltano/mappers/my-test-mapper/venv/lib/python3.11/site-packages/singer_sdk/_singerlib/messages.py", line 114, in __post_init__ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.246973Z [info     ]     if self.time_extracted and not self.time_extracted.tzinfo: cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.247109Z [info     ]                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^ cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.247246Z [info     ] AttributeError: 'str' object has no attribute 'tzinfo' cmd_type=elb consumer=True name=my-test-mapper producer=True stdio=stderr string_id=my-test-mapper
2023-08-08T16:34:04.337947Z [info     ] Incremental state has been updated at 2023-08-08 16:34:04.337835.
2023-08-08T16:34:04.344475Z [error    ] Mappers failed
2023-08-08T16:34:04.344918Z [error    ] Block run completed.           block_type=ExtractLoadBlocks err=RunnerError('Mappers failed') exit_codes=[{'my-test-mapper': 1}] set_number=0 success=False
Need help fixing this problem? Visit http://melta.no/ for troubleshooting steps, or to
join our friendly Slack community.

Run invocation could not be completed as block failed: Mappers failed
```

I believe this means that the `self.time_extracted` member is a string, when it's not expected to be.

### Code

_No response_
