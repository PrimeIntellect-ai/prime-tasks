Incompatible "new-style" formatting without type specifiers
Development version allow for [formatting similar to Python floats](https://mpmath.readthedocs.io/en/latest/general.html#mpmath-mpf-format), including same format specifiers (i.e. `'f'` or `'e'`).  Though, this introduced an incompatibility in case when the format specifier is missing.

On v1.3.0:
```pycon
>>> from mpmath import *
>>> x = mpf(pi)
>>> f"{x}"
'3.14159265358979'
>>> f"{x!s}"
'3.14159265358979'
>>> f"{x!r}"
"mpf('3.1415926535897931')"
>>> f"{x!a}"
"mpf('3.1415926535897931')"
>>> f"{x=}"
"x=mpf('3.1415926535897931')"
```
In the master:
```pycon
>>> from mpmath import *
>>> x = mpf(pi)
>>> f"{x}"  # (!)
'3.1415926535897931'
>>> f"{x!s}"
'3.14159265358979'
>>> f"{x!r}"
"mpf('3.1415926535897931')"
>>> f"{x!a}"
"mpf('3.1415926535897931')"
>>> f"{x=}"
"x=mpf('3.1415926535897931')"
```

A quick fix (not sure if it's a good idea):
```diff
diff --git a/mpmath/libmp/libmpf.py b/mpmath/libmp/libmpf.py
index 9eb24222..3ca77388 100644
--- a/mpmath/libmp/libmpf.py
+++ b/mpmath/libmp/libmpf.py
@@ -1633,7 +1633,7 @@ def format_digits(num, format_dict, prec):
                 strip_last_zero = True

         if precision < 0:
-            precision = repr_dps(prec)
+            precision = prec_to_dps(prec)
         if precision == 0:
             precision = 1

```
The problem is that it breaks `float(format(x)) == float(format(float(x)))` invariant.

### Additional contract requirements

- When formatting an `mpf` without a type specifier, the output must respect `mp.pretty_dps`: with `mp.pretty_dps = 'repr'`, `f'{mp.pi}'` must be `'3.1415926535897931'`; with `mp.pretty_dps = 'str'`, it must be `'3.14159265358979'`.
