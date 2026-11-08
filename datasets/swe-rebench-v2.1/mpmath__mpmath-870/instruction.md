hang in findroot
running the following code snippet will hang at the line of nsolve in the function _calc_abcd_with_sp.

```
from sympy import symbols, nsolve, sqrt

def _calc_abcd_with_sp(phi, abcd0):
    a0, b0, c0, d0 = abcd0
    N0 = sum(abcd0)
    S0 = b0 / d0
    T0 = c0 / d0

    a, b, c, d = symbols("a b c d", Positive=True, Real=True)

    eq1 = N0 - (a + b + c + d)
    eq2 = b - S0 * d
    eq3 = c - T0 * d
    eq4 = phi - (a * d - b * c) / sqrt((a + b) * (c + d) * (a + c) * (b + d))

    print(phi, abcd0, flush=True)
    try:
        solutions = nsolve(
            (eq1, eq2, eq3, eq4), (a, b, c, d), (a0, b0, c0, d0), maxsteps=2, tol=1e-6, verbose=True
        )
    except (
        ValueError,
        ZeroDivisionError,
    ):
        return ()
    # print(phi, abcd0, flush=True)

    a_, b_, c_, d_ = map(float, [sol[0] for sol in solutions.tolist()])

    if a_ < 0 or b_ < 0 or c_ < 0 or d_ < 0:
        return ()
    abcd = round_numbers((a_, b_, c_, d_))
    if not is_valid_abcd(abcd):
        return ()
    return abcd


def round_numbers(numbers):
    rounded = np.floor(numbers).astype(int)

    original_sum = sum(numbers)
    rounded_sum = sum(rounded)
    difference = round(original_sum - rounded_sum)

    for i in np.argsort([n - r for n, r in zip(numbers, rounded)])[::-1][:difference]:
        rounded[i] += 1
    return tuple(rounded.tolist())


def is_valid_abcd(abcd):
    a, b, c, d = abcd
    return a >= 0 and b >= 0 and c >= 0 and d > 0 and a + b > 0 and a + c > 0

phi = -0.44
abcd0 = (38, 34, 0, 49)
_calc_abcd_with_sp(phi, abcd0)
```

### Additional contract requirements

- Solving the four equations from the snippet above (eq1 to eq4, unknowns a, b, c, d) with `mpmath.findroot` in place of `nsolve`, starting from (38, 34, 0, 49) with `maxsteps=2` and `tol=1e-6`, must finish. It may return a solution or raise `ValueError` (including `mpmath.ComplexResult`), but it must not run indefinitely.
