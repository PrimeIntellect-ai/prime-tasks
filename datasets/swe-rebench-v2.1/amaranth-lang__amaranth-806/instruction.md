Wrong normalization for `Const(-16, 4)`
```
>>> Const(-16, 4)
(const 4'sd-16)
```

This const does not fit in 4 bits and should be normalized to 0.
