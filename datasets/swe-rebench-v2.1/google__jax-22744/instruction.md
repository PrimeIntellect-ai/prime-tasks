Binomial and beta-binomial `logpmf` returns NaN and nonzero values when k=n=0 (it should be zero)
### Description

So I am building a model with `jax` + `jaxopt` and was getting some NaN's in my loss function (essentially the negative logpmf of the beta-binomial distribution) during training. Taking a look at the values going in, nothing seemed out of the ordinary, except I noticed that the NaN's coming out corresponded to scenarios where k=n=0. I'm pretty sure the output value of this should be zero, because the probability of getting zero successful events out of zero trials is 100% (and `log(1)==0`) :smile:.

I confirmed this with `scipy`'s version of the beta-binomial and found that it behaved as I expected. I then wondered whether this bug might also be present in the normal (non-beta) binomial and found that while the logpmf output is not NaN, it is generally a small float value rather than 0 exactly. Perhaps it's close enough to zero practically speaking that it is not an issue. You can reproduce the bug and see the comparison with `scipy` by running the following in an interpreter:

```python
Python 3.11.6 (main, Oct  3 2023, 02:51:45) [Clang 14.0.3 (clang-1403.0.22.14.1)] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> import jax.scipy.stats as jst
>>> import scipy.stats as sst
>>> import numpy as np
>>> # compare beta-binomial when k=n=0
>>> a = b = np.linspace(1, 100, 10)
>>> jst.betabinom.logpmf(0, 0, a, b)
Array([nan, nan, nan, nan, nan, nan, nan, nan, nan, nan], dtype=float32)
>>> sst.betabinom.logpmf(0, 0, a, b)
array([0., 0., 0., 0., 0., 0., 0., 0., 0., 0.])
>>> # compare regular binomial when k=n=0
>>> p = np.linspace(0, 1, 10)
>>> jst.binom.logpmf(0, 0, p)
Array([-4.7683716e-07, -4.7683716e-07, -4.7683716e-07, -4.7683716e-07,
       -4.7683716e-07, -4.7683716e-07, -4.7683716e-07, -4.7683716e-07,
       -4.7683716e-07, -4.7683716e-07], dtype=float32)
>>> sst.binom.logpmf(0, 0, p)
array([0., 0., 0., 0., 0., 0., 0., 0., 0., 0.])
```

Looking at `jax`'s source, the problem with the beta-binomial seems to stem from [these lines](https://github.com/google/jax/blob/760deb310e7a5d574ceff03a0e38c807940b3f85/jax/_src/scipy/stats/betabinom.py#L39-L40), [HIDDEN] I think perhaps if you just [HIDDEN] that should fix it. If you look at the [scipy implementation](https://github.com/scipy/scipy/blob/ae3ca70a72ef04547fbc28501009246cef5ee6c8/scipy/stats/_discrete_distns.py#L230-L233) that check isn't present at all. I tested it out locally and it still doesn't evaluate to zero exactly like the regular binomial, but I don't think it's that big of a deal.

```python
>>> logpmf(0, 0, a, b) # [HIDDEN]
Array([-9.536743e-07, -9.536743e-07, -9.536743e-07, -9.536743e-07,
       -9.536743e-07, -9.536743e-07, -9.536743e-07, -9.536743e-07,
       -9.536743e-07, -9.536743e-07], dtype=float32)
```

I am happy to whip up a PR real quick if this makes sense!

### What jax/jaxlib version are you using?

jax==0.4.23, jaxlib==0.4.23

### Which accelerator(s) are you using?

CPU

### Additional system info?

Python 3.11.6, MacOS

### NVIDIA GPU info

_No response_

### Additional contract requirements

- `jax.scipy.stats.binom.logpmf(k, n, p, loc=0)` returns exactly `0` when `k - loc == 0` and `n == 0`, when `k - loc == 0` and `p == 0`, and when `k - loc == n` and `p == 1`.
- `jax.scipy.stats.betabinom.logpmf(k, n, a, b, loc=0)` returns exactly `0` when `k - loc == 0`, `n == 0`, and both `a` and `b` are strictly positive.
- `jax.scipy.stats.betabinom.logpmf(k, n, a, b, loc=0)` returns `nan` when `n` is negative, or when `a` or `b` is not strictly positive.
