wal: ensure wal can be appended to after loading snapshots
I believe that if we load a snapshot at txn `n`, but we have a truncated wal with the last index at txn `n-k`, we could get into a situation where no new records are appended to the WAL, which is not good since the log request queue could grow unboundedly given the wal's nextTx is at `n-k`, but this transaction will never be appended to the log.

I think this is currently happening in production given that the WALs are tiny.
