Add user + password configuration for RethinkDB databases
RethinkDB 2.3.0 supports users and permissions to isolate database access

### Additional contract requirements

- When RethinkDB storage configuration has no username, parsing must return an error containing `requires a username to connect to the db`.
- The parsed RethinkDB storage configuration must retain the configured `storage.username` and `storage.password` values so they can be used to authenticate to the database. `ParseRethinkDBStorage` returns a `RethinkDBStorage` whose `Username` and `Password` fields hold those values.
- Configured credentials must be used to authenticate RethinkDB application connections.
