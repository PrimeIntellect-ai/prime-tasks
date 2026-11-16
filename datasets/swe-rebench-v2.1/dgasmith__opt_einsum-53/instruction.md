Support multi-threading in shared_intermediates
Following up on https://github.com/dgasmith/opt_einsum/pull/43#issuecomment-414661988, the `shared_intermediates` cache is currently not locked.

One option would be to assign the thread id of a unique owner of the cache, such that at least thread conflicts could be detected and reported, rather than mere silent performance degradation.

### Additional contract requirements

The active-cache lookup is specific to the calling thread: while inside a `shared_intermediates` context, `opt_einsum.sharing.get_sharing_cache()` returns the innermost cache yielded to that thread, even when another thread has a concurrent sharing context.
