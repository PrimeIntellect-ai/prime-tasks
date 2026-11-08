[Bug]: Setting `add_record_metadata` should be surfaced as builtin target configuration
### Singer SDK Version

0.14.0

### Python Version

NA

### Bug scope

Targets (data type handling, batching, SQL object generation, etc.)

### Operating System

NA

### Description

The flag is retrieved from config in https://github.com/meltano/sdk/blob/253851e005a92549684959f4f6150abc0617264b/singer_sdk/sinks/core.py#L187-L194

and it's documented in https://github.com/meltano/sdk/blob/1576b5c290396e8875c1daca8e8d920497467486/docs/implementation/record_metadata.md?plain=1#L1-L15

but the target's config schema is not aware of the setting.

[HIDDEN]

### Code

_No response_

### Additional contract requirements

The `add_record_metadata` setting must be represented in the target configuration schema as a boolean flag.
