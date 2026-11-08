Freezing revision for several consequitive queries
Currently, we track that revision is frozen while a single query is in progress, but we don't have a way to freeze the revision for consecutive queries. I think this might be important for correctness for clients which issue multiple queries for a single high-level op.

For example, IDE might ask for types (one query) and control flow info (other query) for syntax highlighting. If a revision bump happens in-between, the end result might be an inconsistent highlighting.

One way to solve this is to turn "highlighting" itself into a query.

Another way is to place onus on consumers to check that revision haven't advanced before merging results of the consecutive queries.

The third way is to provide some explicit API for freezing revisions. This could work with a drop-guard style API, and means [HIDDEN].

### Additional contract requirements

Expose the revision-freezing API as `Runtime::lock_revision`. Holding its returned guard across consecutive queries keeps them on a stable revision: a concurrent write cannot cause those queries to observe different revisions. The guard releases the lock when dropped, allowing the write to proceed.
