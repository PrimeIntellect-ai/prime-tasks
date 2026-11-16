totalBytesProcessed is not exposed from RowIterator
RowIterator resulting from `query_and_wait()` for the new short query mode exposes most of its internal state via properties (cf. e.g. `num_dml_affected_rows`) but does not provide a `total_bytes_processed` property to access `self.totalBytesProcessed`. It would be nice if as many as possible of the same attributes were present to make transitioning to `query_and_wait()` from `query()` as smooth as possible.

I'm sure there are other attributes too but this is the one that I ran into first.
