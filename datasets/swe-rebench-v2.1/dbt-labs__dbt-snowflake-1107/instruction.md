[HIDDEN]
### Is this a new bug in dbt-snowflake?

- [X] I believe this is a new bug in dbt-snowflake
- [X] I have searched the existing issues, and I could not find an existing issue for this bug

### Current Behavior

`show objects` queries can get slow and take up to 3s

### Expected Behavior

`show objects` queries take optimal 300ms

### Steps To Reproduce

1. Run many individual `show objects` queries in sequence

### Relevant log output

_No response_

### Environment

_No response_

### Additional Context

Solution from Snowflake: https://dbt-labs.slack.com/archives/C04R0T4H8ES/p1719874443806149?thread_ts=1719586466.620999&cid=C04R0T4H8ES

### Additional contract requirements

- The `show objects` metadata query issued when fetching a single relation's catalog must use `starts with` instead of `like`.
- Because `starts with` is case-sensitive, the metadata query must be issued against the case-sensitive form of the relation, so that unquoted path parts appear upper-cased in the query while quoted parts are preserved.
- Add a public method `as_case_sensitive(self) -> SnowflakeRelation` on `dbt.adapters.snowflake.relation.SnowflakeRelation`. It returns a new relation in which each path part (database, schema, identifier) is upper-cased when the corresponding quote-policy flag is false, and left unchanged when the flag is true.
