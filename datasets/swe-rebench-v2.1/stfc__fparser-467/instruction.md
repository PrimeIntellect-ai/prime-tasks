Bug matching ALL containing a boolean expression in parentheses
fparser2 crashes when parsing:
```fortran
    integer :: i1, i2
    logical :: equal, var1, var2
    equal = all( (/ var1, var2, (i1==i2) /) )
```
with
```
  File "fparser/src/fparser/two/Fortran2003.py", line 2956, in match
    assert j != -1
```
If the parentheses around `i1==i2` are removed then the parse continues without error.
