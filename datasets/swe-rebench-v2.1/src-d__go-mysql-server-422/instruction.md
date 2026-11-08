Implement show fields from
Implement `SHOW FIELDS FROM <table>` statement.

See: https://github.com/src-d/gitbase/issues/361#issuecomment-427285397

### Additional contract requirements

- `SHOW COLUMNS FROM <table>` and `SHOW FIELDS FROM <table>` are equivalent statements. `SHOW FULL COLUMNS FROM <table>` produces the extended listing.
- A `SHOW COLUMNS`/`SHOW FIELDS` statement may be followed by `WHERE <condition>` or `LIKE <pattern>`, which restrict the produced rows to those whose `Field` column matches.
- The short listing has the columns `Field`, `Type`, `Null`, `Key`, `Default`, `Extra`. The full listing has the columns `Field`, `Type`, `Collation`, `Null`, `Key`, `Default`, `Extra`, `Privileges`, `Comment`.
- The `Null` value is `NO` for a non-nullable column and `YES` for a nullable column. The `Default` value is the column default rendered as text, or empty when the column has no default. In the full listing the `Collation` value is `utf8_bin` for text columns and has no collation value otherwise; an absent collation may be represented as SQL NULL or as an empty string.
- Add a public function `NewShowColumns(full bool, child sql.Node) *ShowColumns` in package `plan` (import path `gopkg.in/src-d/go-mysql-server.v0/sql/plan`). The returned value provides `Schema() sql.Schema`, `RowIter(ctx *sql.Context) (sql.RowIter, error)` and `String() string`.
- `Schema()` returns the short listing columns when `full` is false and the full listing columns when `full` is true.
- `String()` renders the node in a tree-printer friendly form: the short form is `ShowColumns` and the full form is `ShowColumns(full)`.
