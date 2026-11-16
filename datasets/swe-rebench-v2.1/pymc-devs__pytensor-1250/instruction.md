Expose `vecdot`, `vecmat` and `matvec` helpers
### Description

Newer numpy versions introduced the vecmat and matvec (and they had vecdot for a while), which we have internally as different Blockwise versions of `Dot`, just like `matmul`. We should expose those as we do with `matmul`:

https://github.com/pymc-devs/pytensor/blob/5d4e9e0749aa0d33a9db26080a35fdd579aef23d/pytensor/tensor/math.py#L2760-L2841


https://numpy.org/doc/stable/reference/generated/numpy.matvec.html#numpy.matvec
https://numpy.org/doc/stable/reference/generated/numpy.vecmat.html
https://numpy.org/doc/stable/reference/generated/numpy.vecdot.html#numpy.vecdot
