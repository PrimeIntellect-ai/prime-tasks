mpf_bernoulli sometimes results sometimes non-normalized
For example:
```pycon
>>> from mpmath import libmp
>>> libmp.mpf_bernoulli(10, 336, rnd='d')
(0, mpz(5970000938847648365496824257597517243193899889464461616355802030946321480529880395668828220437108430425246665198001), -385, 382)
>>> libmp.mpf_bernoulli(10, 336, rnd='u')
(0, mpz(84838815991583492824145540930622889322789602167979149049242011400143631484097005506851420199682087719), -339, 336)
```
while
```pycon
>>> from mpmath import libmp
>>> libmp.mpf_bernoulli(10, 336, rnd='u')
(0, mpz(5970000938847648365496824257597517243193899889464461616355802030946321480529880395668828220437108430425246665198001), -385, 382)
```

[HIDDEN]

### Additional contract requirements

`mpmath.libmp.mpf_bernoulli(n, prec, rnd=round_fast, plus=False)` must return a
normalized result: the returned mantissa must use at most `prec` bits, and the
value must be rounded according to the caller-supplied rounding mode `rnd`
(`'d'` = round down, `'u'` = round up, `'f'` = round floor, `'n'` = round to
nearest).  For `n = 10`, where `B_10 = 5/66`, the returned value must equal the
correctly rounded value of `5/66` at precision `prec` for the given rounding
mode.
