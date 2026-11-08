Use Dawson function for dispersion
`plasma_dispersion_func` under `mathematics.py` currently uses `erf()` along with some other terms. This can be simplified to Dawson function, [dawsn](https://docs.scipy.org/doc/scipy/reference/generated/scipy.special.dawsn.html), and may even offer some minor speedups if scipy implements it in C code.

### Additional contract requirements

`plasma_dispersion_func` must evaluate the plasma dispersion function through a numerically stable special function rather than through `erf()`, so that the returned value remains finite and accurate for large arguments. Either the Dawson function (`scipy.special.dawsn`) or the Faddeeva function (`scipy.special.wofz`) satisfies this requirement.
