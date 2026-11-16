Registry server: reuse db connections
DB connections are being opened and closed for each database action. The DB connection should be maintained for the lifetime of the server to allow connection pooling and other optimizations such as reuse of prepared statements.

Reference [sql.Open](https://pkg.go.dev/database/sql#Open):

> The returned DB is safe for concurrent use by multiple goroutines and maintains its own pool of idle connections. Thus, the Open function should be called just once. It is rarely necessary to close a DB.

### Additional contract requirements

- Add a public method `Close()` on `RegistryServer` in package `server/registry`. It takes no arguments and returns nothing. Calling it gracefully releases the resources held by the server, closing its database connection.
