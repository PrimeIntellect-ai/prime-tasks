Poor result in log1p(complex)
A case where lop1p of a complex number gets a poor real part:

```python
>>> import mpmath
>>> mpmath.__version__
'1.3.0'
>>> from mpmath import mp, mpc, log, log1p, workprec
>>> c = 1.8370676479640493e-39 - 4.6885882517313053e-20j
>>> complex(log1p(c))
(1.0991429897136409e-39-4.6885882517313053e-20j)
>>> with workprec(500): complex(log1p(c))
(2.93621063767769e-39-4.6885882517313053e-20j)
```

With the higher precision, the real part of the result is entirely different. I don't understand the code:

```python
>>> mp.mag(c), mp.prec
(-63, 53)
```

Because -63 < -53, I expected the code to take the branch that uses a 2-term expansion, which works fine:

```python
>>> c - 0.5*c**2 # matches the high-precision result
(2.93621063767769e-39-4.6885882517313053e-20j)
```

But I must not have found the correct source code, since editing it myself has no visible effect.

The other branch in the code calls `log()` instead after adding 1 to c with double precision:

```python
>>> complex(log(mp.fadd(c, 1, prec=106)))
(1.0991429897136409e-39-4.6885882517313053e-20j) # reproduces the "bad" result
```

It's not enough extra precision to help. In this case,

```python
>>> mp.mag((2*c.real + c.real**2 + c.imag**2))
-127
>>> complex(log(mp.fadd(c, 1, prec=127+53))) # so this is enough
(2.93621063767769e-39-4.6885882517313053e-20j)
>>> complex(log(mp.fadd(c, 1, prec=127+53-2))) # but 2 bits less not quite enough
(2.9362106376776874e-39-4.6885882517313053e-20j)
```

To be clear, "the code" I'm talking about is this, from functions/functions.py:

```python
@defun_wrapped
def log1p(ctx, x):
    if not x:
        return ctx.zero
    if ctx.mag(x) < -ctx.prec:
        return x - 0.5*x**2
    return ctx.log(ctx.fadd(1, x, prec=2*ctx.prec))
```

LATER: found the right source code. [HIDDEN] I have no idea how `ctx.prec` ended up at 63. As shown above, I never changed it from the default 53.

### Additional contract requirements

- For small complex arguments where cancellation would otherwise degrade the result, `log1p` must retain an accurate value, including a real part consistent with the high-precision evaluation shown for the reported input.
