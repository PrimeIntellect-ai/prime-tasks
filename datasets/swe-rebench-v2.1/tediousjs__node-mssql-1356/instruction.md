Custom data type handlers
I'm loading `DATE`, `DATETIME` and `DATETIMEOFFSET(3)` from my SQL server database. I've only tested `DATETIME` with `node-mssql` so far, but it looks like it's parsed into a native JavaScript `Date`, which makes sense. However, I would want to change this so that...:

* `DATE` (`sql.Date`) into `js-joda`s `LocalDate`
* `DATETIME` (`sql.DateTime`) into `js-joda`'s `LocalDateTime`
* `DATETIMEOFFSET(x)` (`sql.DateTimeOffset [scale]`) into `js-joda`'s `ZonedDateTime`

Is there a way to register custom handlers for these types?

### Additional contract requirements

- The library exposes a global `sql.valueHandler` value: a `Map` keyed by SQL data types from `sql.TYPES`.
- `sql.valueHandler.set(type, handler)` registers `handler` for the given type and returns the underlying `Map` instance (the same value as `sql.valueHandler`), so calls can be chained.
- `sql.valueHandler.delete(type)` removes a previously registered handler and returns `true` if an entry existed and was removed, otherwise `false`.
- `sql.valueHandler.clear()` removes all registered handlers and returns `undefined`.
- `sql.valueHandler.has(type)` returns `true` if a handler is registered for the given type, otherwise `false`.
- `sql.valueHandler.size` is the number of handlers currently registered.
- A registered handler is invoked for each cell of its type when rows are materialised, and the value it returns appears in the result recordsets.
