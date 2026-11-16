mass_absolute returns NaN for some negative time-series
I found this while playing with the PAMAP dataset. Haven't been able to reproduce this with random numbers, so here's the relevant data and code.
```python
Q = np.array([-13.09, -14.1 , -15.08, -16.31, -17.13, -17.5 , -18.07, -18.07,
       -17.48, -16.24, -14.88, -13.56, -12.65, -11.93, -11.48, -11.06,
       -10.83, -10.67, -10.59, -10.81, -10.92, -11.15, -11.37, -11.53,
       -11.19, -11.08, -10.48, -10.14,  -9.92,  -9.99, -10.11,  -9.92,
        -9.7 ,  -9.47,  -9.06,  -9.01,  -8.79,  -8.67,  -8.33,  -8.  ,
        -8.26,  -8.  ,  -7.54,  -7.32,  -7.13,  -7.24,  -7.43,  -7.93,
        -8.8 ,  -9.71])
print(stumpy.core.mass_absolute(Q, Q))
```
I get `nan`, but of course it should be `0`. The problem is some float imprecision in `_mass_absolute` that leads to negative values that can't be properly `np.sqrt`ed.

Easy to fix, of course. A test for this edge case should be added as well.
