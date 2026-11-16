This package assumes that `*` is commutative
Methods like the following are generally wrong (consider multiplying a `Quaternion` by a `Quantity{Quaternion}`):
https://github.com/PainterQubits/Unitful.jl/blob/e2aa6f8bb66ddf37adc0d33c7a40958dfcaaadaa/src/quantities.jl#L32
