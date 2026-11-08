cancellation of a single query affects multiple queries in the same session

### What version of Cassandra are you using?
3.4.0
### What version of Gocql are you using?
latest master at https://github.com/gocql/gocql/commit/df4b9cc330307b4a196f255fc0d1e8a53cabfbcd
### What did you do?
- start a new cassandra session
- run a statement in multiple queries multiple times concurrently in multiple Go routines each.
- statements created with `session.Query(selectStatement, x).WithContext(ctx)`
- each statement gets a different `ctx`
- one of thoese `ctx` variables is an already canceled context
### What did you expect to see?
Only the statement with the canceled context should receive the cancellation error.
### What did you see instead?
All statements running concurrently with the cancelled statement get cancelled.
