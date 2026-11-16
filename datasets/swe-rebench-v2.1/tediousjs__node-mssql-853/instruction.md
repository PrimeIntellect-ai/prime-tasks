[Feature Request] Set readOnlyIntent with connection string
If I have to build connection string and set readOnlyIntent how can I set ? Below is what I am trying to do ..

const connectionString = `Server=${blah};Database=${blah};UID=${username};
PWD=${blah};ApplicationIntent=ReadOnly`; but not working


### Software versions
  * node-mssql: 4.3.0

### Additional contract requirements

- The module `lib/connectionstring.js` exposes a function `resolve(connectionString, driver)` that parses a SQL Server connection string into a configuration object.
- The returned configuration object contains an `options` sub-object with a boolean property `readOnlyIntent`.
- `options.readOnlyIntent` is `true` when the connection string contains `ApplicationIntent=ReadOnly`.
- `options.readOnlyIntent` is `false` when the connection string contains `ApplicationIntent=ReadWrite`.
