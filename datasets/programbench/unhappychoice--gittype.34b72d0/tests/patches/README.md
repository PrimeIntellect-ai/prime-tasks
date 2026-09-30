# GitType verifier fixture repairs

Keep the upstream active case set and assertions. Terminal fixtures use small,
committed input repositories under `/workspace`: the pinned executable excludes
paths containing `tmp` or `temp`. Scanning the entire benchmark checkout otherwise
makes unrelated fixture files and repository size affect typing tests.

Each terminal test receives a fresh HOME. Trending fixtures use the executable's
actual `.gittype/trending_cache` path and bundled repository data. Version checks
use timestamped fixtures for the pinned 0.8.0 executable, with 0.9.0 only in tests
that explicitly exercise update notices. These caches are scoped to terminal
tests; persistence tests retain their empty-home preconditions.

The test process adopts, terminates, and reaps descendants left by PTY helpers,
including children that create a new session. Cleanup is limited to children
created by the current test. Eight workers and 32 GiB keep the original terminal
and persistence checks within their timeouts. Ignored upstream cases remain in
the suite; no active cases are removed or converted to skips.
