LinearAlgebra.hermitian is incorrect
https://github.com/jump-dev/JuMP.jl/blob/119569556f5fd28d12b012f4c94d8dfdaca6d65a/src/JuMP.jl#L1058
doesn't seem to match the docstring of `LinearAlgebra.hermitian`:

> If `A` is a Number, its real part is returned converted back to the input type.
