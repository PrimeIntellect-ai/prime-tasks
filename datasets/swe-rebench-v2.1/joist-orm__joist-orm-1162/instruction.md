newPgConnectionConfig does not handle ssl settings specified in connection string
`newPgConnectionConfig` currently does its own parsing of the DATABASE_URL here:

https://github.com/joist-orm/joist-orm/blob/004dad18dbeb69430fe66481ec39cc5f2354519c/packages/utils/src/connection.ts#L37-L48

This does not pass through any SSL options specified in the connection string (e.g. `sslmode=require`) and means it is impossible to use with any databases that require this, notably Vercel Postgres.

It would be good to at least handle `ssl=true` to mitigate this.

It seems to me given `createKnex` and the `Client` constructor from the `pg` module both already allow a connection string to be passed directly and handle SSL options correctly, [HIDDEN]

The exception is `Pool` which requires an object.

I have made a very simple patch but by all means disregard if there is a better alternative.

### Additional contract requirements

- When a `DATABASE_URL` contains the query parameter `ssl=true`, the returned connection config has `ssl: true`.
- When the individual `DB_*` variables are used, the `DB_SSL` variable set to `"true"` or `"1"` enables SSL, i.e. the returned connection config has `ssl: true`.
- When no SSL signal is present, the returned connection config does not have `ssl: true`.
