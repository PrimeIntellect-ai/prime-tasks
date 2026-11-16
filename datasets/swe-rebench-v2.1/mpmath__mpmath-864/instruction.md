zeta(2, -2) crashes.
```
>>> from mpmath import *
>>> mp.dps = 100
>>> zeta(2, -2)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/functions/zeta.py", line 580, in zeta
    return +ctx._hurwitz(s, a, d, **kwargs)
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/functions/zeta.py", line 604, in _hurwitz
    T1, T2 = _hurwitz_em(ctx, s, a, d, prec+10, verbose)
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/functions/zeta.py", line 675, in _hurwitz_em
    l = ctx._zetasum(s, M1+a, M2-M1-1, [d])[0][0]
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/functions/zeta.py", line 749, in _zetasum
    return [ctx.fsum((a+k)**negs for k in xrange(n+1))], []
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/ctx_mp_python.py", line 849, in fsum
    for term in terms:
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/functions/zeta.py", line 749, in <genexpr>
    return [ctx.fsum((a+k)**negs for k in xrange(n+1))], []
  File "<string>", line 9, in __pow__
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/libmp/libelefun.py", line 328, in mpf_pow
    return mpf_pow_int(s, (-1)**tsign * (tman<<texp), prec, rnd)
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/libmp/libmpf.py", line 1073, in mpf_pow_int
    return mpf_div(fone, inverse, prec, rnd)
  File "/home/palaiologos/.local/lib/python3.10/site-packages/mpmath/libmp/libmpf.py", line 960, in mpf_div
    raise ZeroDivisionError
ZeroDivisionError
```

However, WolframAlpha claims that it is simply complex infinity:

https://www.wolframalpha.com/input?i=hurwitz%282%2C-2%29

### Additional contract requirements

- When `a` is a negative integer, including in `zeta(2, -2)`, `zeta` must signal the mathematically infinite case with `ValueError` rather than expose an internal `ZeroDivisionError`.
