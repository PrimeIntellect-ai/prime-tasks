[Bug]: Too many `Properties () were present in the '...' stream` messages
### Singer SDK Version

0.13.1

### Python Version

NA

### Bug scope

Taps (catalog, state, stream maps, etc.)

### Operating System

Any

### Description

From @visch in Slack:

> Seeing a lot of
> ```
> time=2022-11-09 20:52:36 name=tap-activedirectory level=INFO message=Properties () were present in the 'users' stream but not found in catalog schema. Ignoring.
> ```
> Lately, anyone else? empty properties() object? Maybe a sdk bug?

Issue is in line https://github.com/meltano/sdk/blob/a3f64db222f9f046fff16910a024680979335790/singer_sdk/helpers/_typing.py#L230

### Code

_No response_

### Additional contract requirements

- `conform_record_data_types(stream_name: str, record: dict, schema: dict, logger: logging.Logger) -> dict` in `singer_sdk/helpers/_typing.py` returns a dictionary in which each record value has been converted to a JSON-compatible type according to the schema.
- When the record contains properties not defined in the schema, an INFO log message is emitted. For an unmapped property named `absent` in stream `test-stream`, the message must include `Properties ('absent',) were present in the 'test-stream' stream but not found in catalog schema. Ignoring.`
- When every property in the record is defined in the schema, no such message is logged.


- - For each tested `updatedAt` datetime representing `2021-08-25T20:05:28` (with an offset, `Z`, or no timezone), the returned value must be exactly `"2021-08-25T20:05:28+00:00"`.
