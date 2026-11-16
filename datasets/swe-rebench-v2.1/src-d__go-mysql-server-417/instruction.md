Show databases
Implement a command to show databases.

_Originally posted by @erizocosmico in https://github.com/src-d/gitbase/issues/361#issuecomment-427285397

### Additional contract requirements

- `SHOW DATABASES` lists the names of the databases in the current catalog, sorted alphabetically.
- The result of `SHOW DATABASES` has a single text column named `database`.
- Add a public function `NewShowDatabases()` in package `plan` (file `sql/plan/showdatabases.go`) that returns a `*plan.ShowDatabases` value implementing `sql.Node`. `ShowDatabases` has an exported `Catalog` field of type `*sql.Catalog`; it is nil when the node is created and is set to the current catalog when the node is analyzed.
- Parsing the statement `SHOW DATABASES` yields a `*plan.ShowDatabases` node.
