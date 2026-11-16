[query] Query builder related types should be public on crate level

### Additional contract requirements

- The following public API types must be accessible through crate-root imports: `Comparison`, `CountComparison`, `Db`, `DbElement`, `DbError`, `DbId`, `DbKey`, `DbKeyOrder`, `DbKeyValue`, `DbValue`, `InsertAliasesQuery`, `InsertEdgesQuery`, `InsertNodesQuery`, `InsertValuesQuery`, `Query`, `QueryBuilder`, `QueryCondition`, `QueryError`, `QueryId`, `QueryIds`, `QueryMut`, `QueryResult`, `QueryValues`, `RemoveAliasesQuery`, `RemoveQuery`, `RemoveValuesQuery`, `SearchQuery`, `SelectAllAliases`, `SelectKeyCountQuery`, `SelectKeysQuery`, `SelectQuery`, `SelectValuesQuery`, `Transaction`, and `TransactionMut`.
