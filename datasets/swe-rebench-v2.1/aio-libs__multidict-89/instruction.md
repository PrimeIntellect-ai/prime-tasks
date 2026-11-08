Force keys to str instances
Right now a key type is dark corner: it could be str, istr or something other.
For sake of further optimizations it should be `str` always.

Passing `istr` as key to any miltidict API is still allowed and encouraged: it saves execution time by getting rid of `s.title()` conversion.

But `istr` type is ambiguous by it nature: we can define equality for `str` and `istr` by comparing their *canonical* representations but ordering is cumbersome.
Ordering by canonical reprs leads to very tricky errors, the same for *original* reprs.
Also CPython is very optimized for `str` but not classes derived from it.

I believe the change doesn't touch our users but aiohttp might get speedup on implementing the issue.
