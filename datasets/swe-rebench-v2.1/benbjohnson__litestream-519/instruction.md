Unclean close leaves Litestream in weird state
I've been using Litestream as a library and tried a couple of things to abuse it since the usage pattern is a bit different than when using it as a separate process.

What I'm seeing is that the final sync at the beginning of Close() will fail due to this because I had sqlite3 cli just writing while closing (and rolling in the WAL): `cannot verify wal state: stat foo/bar.db-wal: no such file or directory`. This might be fine to ignore but the caller doesn't know it and calling Close() again will fail because the underlying database connection has already been closed and will always return an error at that point.

This is very much an edge case of an edge case and it shouldn't ever really happen but the way database Close() is structured it's designed to ignore all errors and just continue but it might be better to return early and allow calling it more than once to retry if it's a passing issue or handle the errors more gracefully. Now because it's designed to ignore errors the caller needs to assume the database is somewhat closed and ignore the returned error and at most log it.

### Additional contract requirements

If Close encounters an error during its final sync, it must still attempt shutdown cleanup and return an error to the caller. When Close returns, the Litestream instance is shut down and no longer holds the database file open, even if synchronization failed. A caller should handle the returned error as a failed final sync on a closed instance rather than retrying Close on that same instance.
