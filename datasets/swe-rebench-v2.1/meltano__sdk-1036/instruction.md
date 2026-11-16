bug: Tables not created if no records arrive with `SQLSink`
### Singer SDK Version

0.11.1

### Python Version

3.8

### Bug scope

Targets (data type handling, batching, SQL object generation, etc.)

### Operating System

MacOS

### Description

With non-SDK Targets it is common for schema/table objects to be created on arrival of a `SCHEMA` singer message before and regardless of if any `RECORD` messages ever arrive. This can be important for downstream testing in tools such as `dbt` where `dbt` will error on missing entities rather than proceed to run tests. This may be less of a bug and more of an unexpected behaviour coming from other SQL-based targets.

### Code

_No response_

### Additional contract requirements

- For a SQLite SQLSink processing a stream named `<schema>-<table>` with a `SCHEMA` message followed by a `RECORD` message, it must attempt `CREATE SCHEMA <schema>`. This must raise `sqlalchemy.exc.OperationalError` whose `statement` is exactly `CREATE SCHEMA <schema>`.
