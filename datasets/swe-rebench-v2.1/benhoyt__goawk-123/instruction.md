[HIDDEN]
In `[HIDDEN]` we currently loop through functions to resolve their parameter types in Go's map iteration order (which is randomized), so if you have a whole bunch of functions with unknown types (e.g., functions that just pass their parameter to another function), only a few will get resolved each iteration, and we'll have to do many iterations. Each iteration is O(N) in the number of functions, so the overall process is O(N^2) in the worst case. This is uncommon for real AWK code, but very bad for pathological cases.

There was an iteration maximum that was 10,000. But for the pathological case of thousands of such functions that took ages (over a minute, and I didn't wait any longer). So in https://github.com/benhoyt/goawk/commit/afcb42a9f8889c2a38da7f138d673fd4da6e6a08 I reduced the max iterations to 500, which takes 100ms or so to resolve. It would be highly unlikely for AWK scripts to have 500 functions with unresolved types.

[HIDDEN]

### Additional contract requirements

- Parsing an AWK program whose functions form a long chain of parameter pass-throughs (thousands of functions) must succeed without an error.
- Types inferred from a function parameter at the end of a pass-through call chain must be preserved for callers earlier in the chain.
- Resolving parameter types on long pass-through chains must avoid quadratic worst-case growth as the chain grows.
