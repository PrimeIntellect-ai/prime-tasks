Incompatible (wrt CPython) formatting for format(mpmath.mpf(9.995074823339339e-05), '.0g')
```pycon
>>> format(9.995074823339339e-05, '.0g')
'0.0001'
>>> format(mpmath.mpf(9.995074823339339e-05), '.0g')
'1e-04'
```
see https://github.com/mpmath/mpmath/actions/runs/11398339589/job/31715210493
