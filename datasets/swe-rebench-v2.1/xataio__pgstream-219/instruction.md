[Snapshots] Repeatable pgdump/pgrestore snapshot support
Currently the snapshot processor supports snapshot history tracking. Snapshot requests are tracked and stored along with their status. When stopping/starting `pgstream` after a snapshot has been performed, the recorded snapshot history will be checked and the snapshot will be retried if there was an error, but will otherwise be skipped.

If the snapshot history tracking is not enabled, then on each restart of `pgstream` the snapshot will be performed as per the configuration provided. If the same snapshot needs to be performed at a given cadence (ex., nightly), the current implementation will likely error after the first snapshot, especially if relying on `pg_dump/pg_restore`, since the resources would already exist. The data snapshot would also result in dataloss if the existing data already existed in the target, especially for cases where the insert/upsert path is different (pogstres processor).

The `pg_dump/pg_restore` implementation should allow to clean the target database before performing the next snapshot, to support repeatable snapshots. This would be the equivalent of having an initial snapshot and continuous replication to keep track of the changes, but with a sync delay in line with the selected cadence.

### Additional contract requirements

- Add a public error type `ErrRelationAlreadyExists` (a struct) in package `github.com/xataio/pgstream/internal/postgres`.
- Add a public type `PGRestoreErrors` in package `github.com/xataio/pgstream/internal/postgres` with:
  - `NewPGRestoreErrors(errs ...error) *PGRestoreErrors`, which classifies `ErrRelationAlreadyExists` errors as ignored and every other error as critical.
  - `(*PGRestoreErrors).Error() string`, returning the concatenated messages of the critical and ignored errors, or an empty string when there are none.
  - `(*PGRestoreErrors).HasCriticalErrors() bool`, reporting whether at least one critical error is present.
  - `(*PGRestoreErrors).GetIgnoredErrors() []error`, returning the errors classified as ignored.
- Add a function `newDMLAdapter(action string) (*dmlAdapter, error)` in package `github.com/xataio/pgstream/pkg/wal/processor/postgres`. It accepts the values `""`, `"error"`, `"update"` and `"nothing"` and returns the sentinel error `errUnsupportedOnConflictAction` for any other value.
- Add a sentinel error `errUnsupportedOnConflictAction` in package `github.com/xataio/pgstream/pkg/wal/processor/postgres`.
- The postgres writer (`NewBatchWriter` in package `github.com/xataio/pgstream/pkg/wal/processor/postgres`) must support a configurable insert on-conflict action, set through the `OnConflictAction` field of its `Config`, with the values `error` (the default), `update` and `nothing`. Any other value makes `NewBatchWriter` return an error:
  - `error`: an insert conflict is treated as an error and the generated insert has no `ON CONFLICT` clause.
  - `nothing`: an insert conflict is ignored, generating an `ON CONFLICT ... DO NOTHING` clause.
  - `update`: an insert conflict updates the existing row, generating an `ON CONFLICT ... DO UPDATE` clause. When the event has no primary key metadata, the default `error` behaviour is used.
