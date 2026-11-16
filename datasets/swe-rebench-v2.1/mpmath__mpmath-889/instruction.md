Negative integer order of the BesselI function
mpmath version: 1.3.0

I am using mpmath to generate values for verification of my own complex Bessel function calculation routine.
https://github.com/tk-yoshimura/ComplexBessel

I have discovered that mpmath cannot compute for large negative integers in Bessel I functions, even though it can use the inversion formula.
https://dlmf.nist.gov/10.27

Example:

```py
import mpmath as mpf

mpf.mp.dps = 64

x = 2

nus = [31, 32, 63, 64, 127, 128,
      -31, -31.25, -32, -32.25,
      -63, -63.25, -64, -64.25,
      -127, -127.25, -128, -128.25
]

for nu in nus:
    print(f"nu = {nu}, x = {x}")

    try:
        y = mpf.besseli(nu, x)
        print(f"{mpf.nstr(y, 40, strip_zeros=False, min_fixed=2, max_fixed=1)}")
    except ValueError as e:
        print(e)

    print("\n")
```

Error Message:
```
nu = -127, x = 2

hypercomb() failed to converge to the requested 216 bits of accuracy
using a working precision of 4814 bits. The function value may be zero or
infinite; try passing zeroprec=N or infprec=M to bound finite values between
2^(-N) and 2^M. Otherwise try a higher maxprec or maxterms.
```

### Additional contract requirements

- At 64 decimal digits, `besseli(-127, 2)` must compare equal to `besseli(127, 2)`.
