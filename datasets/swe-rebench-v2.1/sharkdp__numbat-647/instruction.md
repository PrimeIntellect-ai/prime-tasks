`NaN < 0` errors
I would expect that `NaN < 0` be `false`, but instead it gives

```
>>> NaN < 0.0
error: runtime error
 = Conversion error: unit '' can not be converted to ''
```
