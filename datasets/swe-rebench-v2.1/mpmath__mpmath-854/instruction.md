log1p(x) with real x returns a complex value when x is sufficiently small.
When the real input `x` is small enough, `log1p(x)` returns a complex number, with imaginary part 0:

```
In [1]: import mpmath

In [2]: mpmath.__version__
Out[2]: '1.4.0a2.dev93+g9b99f41'

In [3]: from mpmath import mp

In [4]: mp.dps = 25

In [5]: mp.log1p(6e-30)  # unexpected complex result
Out[5]: mpc(real='5.999999999999999799369291483e-30', imag='0.0')

In [6]: mp.log1p(7e-30)  # slightly bigger input gives a real result.
Out[6]: mpf('7.000000000000000583354944253e-30')

```

### Additional contract requirements

- For complex inputs `0.1 + 0j` and `1e-30 + 0j`, `log1p` returns a complex result, even though the imaginary part is zero.
