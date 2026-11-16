Cos returns invalid interval
Reduced after much effort:
```
k = [interval(0.0,0.0625), interval(0.0625,0.125), interval(0.0,0.125)]
@show x = (k[1] * 4 + k[2] * 4 + k[3] * 4)
@show cos(2 * π * x)
@show cospi(2x)
```
```
x = k[1] * 4 + k[2] * 4 + k[3] * 4 = [0.25, 1.25001]_com_NG
cos(2 * π * x) = [3.06161e-16, 6.12324e-17]_com_NG
cospi(2x) = [-1.0, 1.0]_com_NG
```
Cos is just plainly wrong here. Cospi appears to be fine.
