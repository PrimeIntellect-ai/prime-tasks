Hankel functions incorrect for large imaginary parts and standard precision
For example:
```
>>> hankel1(1,1+30j)
mpc(real='0.0', imag='0.0')
>>> hankel2(1,1-30j)
mpc(real='0.0', imag='0.0')
```
whereas Mathematica gives
```
In[1]:= HankelH1[1, 1. + 30 I]
Out[1]= -7.25495*10^-15 - 1.17346*10^-14 I
In[2]:= HankelH2[1, 1. - 30 I]
Out[2]= -7.25495*10^-15 + 1.17346*10^-14 I
```
Correct values can be found by increasing the precision, but this should be automatic as clearly Mathematica is doing.

The problem arises because the standard definitions of the functions involve two terms with many digits in common, and there need to be sufficient digits available when they are combined.
