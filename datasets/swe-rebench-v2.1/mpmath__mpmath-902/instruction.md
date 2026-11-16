Unexpected Result from laguerre with inf input
mpmath version: 1.1.0

I'm no expert on this function, but it appears that the expected behavior for `laguerre(1, a, b)` is to return `1 + a - b`. SciPy agrees with this. However, when `b` is `inf`, the return appears to consistently be `1 + a` when one might expect a negative infinity. This is what SciPy and GSL do in this situation. Interestingly, the fp version of laguerre takes a different route entirely, throwing a `NoConvergence` exception.

```
Python 3.6.8 (default, Oct  7 2019, 12:59:55)
[GCC 8.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> from mpmath import *
>>> from scipy import special
>>> mp.laguerre(1, 2, 5)
mpf('-2.0')
>>> mp.laguerre(1, 2, mp.inf)
mpf('3.0')
>>> mp.laguerre(1, 7.2, mp.inf)
mpf('8.1999999999999993')
>>> fp.laguerre(1, 7.2, fp.inf)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/local/lib/python3.6/dist-packages/mpmath/ctx_fp.py", line 57, in f_wrapped
    return f(ctx, *args, **kwargs)
  File "/usr/local/lib/python3.6/dist-packages/mpmath/functions/orthogonal.py", line 348, in laguerre
    return ctx.hypercomb(h, [a], **kwargs)
  File "/usr/local/lib/python3.6/dist-packages/mpmath/functions/hypergeometric.py", line 127, in hypercomb
    [ctx.rgamma(b) for b in beta_s] + \
  File "/usr/local/lib/python3.6/dist-packages/mpmath/functions/hypergeometric.py", line 222, in hyper
    if   q == 1: return ctx._hyp1f1(a_s, b_s, z, **kwargs)
  File "/usr/local/lib/python3.6/dist-packages/mpmath/functions/hypergeometric.py", line 342, in _hyp1f1
    v = ctx.hypsum(1, 1, (atype, btype), [a, b], z, **kwargs)
  File "/usr/local/lib/python3.6/dist-packages/mpmath/ctx_fp.py", line 213, in hypsum
    raise ctx.NoConvergence
mpmath.libmp.libhyper.NoConvergence
>>> special.eval_genlaguerre(1, 2, fp.inf)
-inf
>>> special.eval_genlaguerre(1, 7.2, fp.inf)
-inf
```
