polylog at negative floating point infinity
```
>>> mpmath.polylog(2, -1e10)
mpf('-266.73983959066811')

>>> mpmath.polylog(3, -1e10)
mpf('-2072.554598906404')

>>> mpmath.polylog(4, -1e10)
mpf('-12150.509195825773')

>>> mpmath.polylog(5, -1e10)
mpf('-57328.817524624101')
```
That is, polylog limits to -infinity as x -> -infinity

If we try evaluating at -infinity, we sometimes get reasonable but not ideal results:
```
>>> mpmath.polylog(2, -inf)
mpf('nan')

>>> mpmath.polylog(3, -inf)
mpf('nan')
```
(`-inf` would be a better answer.)


For some other values, we can get garbage answers:
```
>>> mpmath.polylog(4, -inf)
mpf('0.0')

>>> mpmath.polylog(5, -inf)
mpf('0.0')
```
