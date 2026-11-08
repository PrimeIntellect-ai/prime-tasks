USE command to change database
Implement use command to change the database in use.

More info: https://github.com/src-d/gitbase/issues/361#issuecomment-427285397

### Additional contract requirements

- Executing `USE <name>` selects the database `<name>` as the current database and produces no result rows. If no database named `<name>` exists, the statement fails with an error.
- Add a public method `CurrentDatabase() string` on `Catalog` in package `sql` that returns the name of the currently selected database, or the empty string if none has been selected.
- Add a public method `SetCurrentDatabase(db string)` on `Catalog` in package `sql` that sets the name of the currently selected database.
- Add a public method `AddDatabase(db sql.Database)` on `Catalog` in package `sql` that registers the database and, if no current database has been selected yet, makes the added database the current one.
- Add a public method `AllDatabases() Databases` on `Catalog` in package `sql` that returns all databases registered in the catalog.
- The `UnresolvedDatabase` type in package `sql` must be constructible from a database name string, e.g. `sql.UnresolvedDatabase("foo")`, and its `Name()` must return that name.
- Add a public function `NewUse(db sql.Database) *Use` in package `sql/plan` that creates a plan node for the `USE` statement targeting `db`.
