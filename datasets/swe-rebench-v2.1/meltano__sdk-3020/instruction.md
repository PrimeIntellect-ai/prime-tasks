bug: Incorrect table name resolved if stream name is hyphenated
### Singer SDK Version

0.44.3

### Is this a regression?

- [ ] Yes

### Python Version

NA

### Bug scope

Targets (data type handling, batching, SQL object generation, etc.)

### Operating System

_No response_

### Description

For SQL targets, if a stream name is hyphenated it is assumed to be fully-qualified and the part after the last hyphen is taken as the table name. In our case, we have a tap stream name of `tap_bigquery-weekly_fuel_prices` and expect a table of name in similar shape to be created in Snowflake - instead, `weekly_fuel_prices` is resolved which is not desirable is our case. Is there a reason for this behaviour?

https://github.com/meltano/sdk/blob/881ffd2041c9eca9c50a5e94ffe61a121579ef61/singer_sdk/sinks/sql.py#L76-L85

### Link to Slack/Linen

_No response_

### Additional contract requirements

- When a SQL target has `default_target_schema` configured, use the full stream name as the table name and the configured value as the schema. Thus `tap_bigquery-weekly_fuel_prices` remains the table name.
- Without a configured `default_target_schema`, retain the existing interpretation of hyphenated stream names as qualified names: the final segment is the table name and, when applicable, the preceding segment is the schema.
