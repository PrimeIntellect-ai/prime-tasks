wal: truncations can sometimes unexpectedly fail
In #428, CI uncovered an interesting edge case in our WAL usage. We have two goroutines: one in https://github.com/polarsignals/frostdb/blob/06fe1fc7c4904417cfbe9bf89fb4acb0e9b190e3/wal/wal.go#L178
and another arbitrary goroutine that can perform truncations concurrently:
https://github.com/polarsignals/frostdb/blob/06fe1fc7c4904417cfbe9bf89fb4acb0e9b190e3/wal/wal.go#L282

The edge case is that a goroutine logs a record with index `k` (e.g. block persistence) and then performs a truncation at that same index. If the `run` goroutine has not read and logged the record with this index, the truncation returns an `out of range` error, since the expected index has not been persisted yet.

To fix these cases, we should [HIDDEN]

### Additional contract requirements

- A truncation requested at index `k` must not be applied before a pending record at index `k` has been persisted. It must not fail with an out-of-range error solely because that record is still pending.
- Truncating through index `k` retains the record at `k` and advances the earliest retained index according to the WAL's existing inclusive boundary semantics.
