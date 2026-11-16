Not all restored snapshot images are cleaned up
Remove all applied snapshot images whenever possible.

### Additional contract requirements

- After a snapshot is applied, the on-disk image of the applied snapshot is
  removed when the shard's persistent log index equals the applied snapshot's
  index. When the persistent log index differs from the applied snapshot's
  index, the applied snapshot's image is retained.
- After a snapshot is applied, snapshot records older than the applied snapshot
  are removed from the log database while the applied snapshot's record is
  retained, so GetAllSnapshots returns only the applied snapshot record.
