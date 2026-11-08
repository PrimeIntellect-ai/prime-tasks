Raise warning when it is not feasible to get at least one pair of non-trivial motif
As explained [here](https://github.com/TDAmeritrade/stumpy/discussions/1076#discussioncomment-12432542), it is possible to have `T` and `m` that result in 0 subsequence that satisfy the exclusion rule, i.e. `|i - j| > excl_zone`, where `i` and `j` are the start index of two subsequences `T[i, i + m]` and `T[j : j + m]`.


See Example below:
```
import numpy as np
import stumpy

T = np.random.rand(10)
m = 8

out = stumpy.stump(T, m)

# out
[[inf -1 -1 -1]
 [inf -1 -1 -1]
 [inf -1 -1 -1]]
```

In this example, `len(T)` is 10, and `m = 8`, and the start index of subsequences are `0, 1, 2`. However, since the [default] `excl_zone` is `2`, then it means there is no `i,j` in `{0, 1, 2}` that satisfies the exclusion rule. It would be a good idea to raise warning in such scenario. As suggested [here](https://github.com/TDAmeritrade/stumpy/discussions/1076#discussioncomment-12432645), `core.check_window_size` seems to be a good place for raising that warning.

### Additional contract requirements

- Emit a warning only when no pair of subsequence start indices satisfies the exclusion rule. Do not warn when at least one eligible pair exists, even if some individual subsequences have no eligible neighbor.
