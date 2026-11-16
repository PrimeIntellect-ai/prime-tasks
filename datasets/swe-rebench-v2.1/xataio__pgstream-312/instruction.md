Syntax error when building create table query
In `postgres_wal_ddl_adapter.go` we are doing a syntax error when building `create table` query:

```go
func (a *ddlAdapter) buildCreateTableQuery(schemaName string, table schemalog.Table) *query {
	createQuery := fmt.Sprintf("CREATE TABLE IF NOT EXISTS %s (", quotedTableName(schemaName, table.Name))
	uniqueConstraints := make([]string, 0, len(table.Columns))
	for _, col := range table.Columns {
		[HIDDEN]
		// if there's a unique constraint associated to the column, and it's not
		// the primary key, explicitly add it
		if uniqueConstraint := a.buildUniqueConstraint(col); uniqueConstraint != "" && !slices.Contains(table.PrimaryKeyColumns, col.Name) {
			uniqueConstraints = append(uniqueConstraints, uniqueConstraint)
		}
	}
```

Here we add a comma after each column. This causes a syntax error if there's no unique constraint or primary key on the table. Resulting in a query like: `CREATE TABLE IF NOT EXISTS "test_sc"."test_table" ("a" integer,)`

### Additional contract requirements

- For the table with no primary key or unique constraint, the generated SQL must match `CREATE TABLE IF NOT EXISTS %s (\n"id" uuid NOT NULL,\n"name" text,\n"age" int NOT NULL DEFAULT 0)`, where `%s` is the quoted table name.
- For a table with a unique constraint on "name" and a primary key on "id", the generated SQL must match `CREATE TABLE IF NOT EXISTS %s (\n"id" uuid NOT NULL,\n"name" text,\n"age" int NOT NULL DEFAULT 0,\nUNIQUE ("name"),\nPRIMARY KEY ("id")\n)`, where `%s` is the quoted table name.
