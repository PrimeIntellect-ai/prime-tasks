Take persistent log index into consideration when compacting logs

### Additional contract requirements

- The data storage exposes `GetPersistentLogIndex(shardID uint64) (uint64, error)`, which returns the highest raft log index for the given shard that is guaranteed to be retained after a restart.
- When a CompactLog request is executed, the requested compact index must never be greater than the shard's persistent log index; raft log entries at or below the persistent log index must be retained.
- If retrieving the persistent log index fails, executing the CompactLog request must fail and return an error.
