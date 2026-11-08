The memory usage is growing unlimitedly
# issue

The memory usage is growing unlimitedly as the revision table grows.

# usecase

Especially when using atlas for DML frequently, `atlas_schema_revisions` table grows rapidly and so does the memory usage, which is not scalable.

# code

https://github.com/ariga/atlas/blob/5bb5954fa4b91abb11dad4dd95d87164896bd59e/cmd/atlas/internal/migrate/migrate.go#L148-L151

### Additional contract requirements

- `migrate.Revision` exposes a public field `PartialHashes []string` that holds the hashes of the statements applied so far for a partially applied migration.
- After a migration file has been applied successfully, the revision record stored by the `RevisionReadWriter` must have its `PartialHashes` cleared (empty), so that completed revisions no longer retain per-statement partial hashes.
