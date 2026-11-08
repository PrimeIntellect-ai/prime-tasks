[FEATURE] `execute` query command
The Return is very basic with just “OK” or “Error”.

POST /automation/v1/queries/{{queryID}}/actions/start/

should support
- `*` for BUs
- marketlist for BUs
- multiple query keys

later, the same command can be expanded for starting journeys, triggeredSends, ...

### Additional contract requirements

- The marketlist selector is `*`: it targets every BU listed under the configured credentials. Each selected BU must receive a start request for every requested query.
- The command is invoked as `execute <BU> <TYPE> <KEY>`: `<BU>` is the business unit (or `*`), `<TYPE>` is the metadata type (`query` for this request), and `<KEY>` is one or more query keys separated by commas.
