erfcinv does not support BigFloat
erfc supports BigFloat, but not erfcinv:

ERROR: MethodError: no method matching erfcinv(::BigFloat)
Closest candidates are:
  erfcinv(::Missing) at /home/fabien/.julia/packages/SpecialFunctions/qmwwl/src/SpecialFunctions.jl:77
  erfcinv(::Float32) at /home/fabien/.julia/packages/SpecialFunctions/qmwwl/src/erf.jl:394
  erfcinv(::Float64) at /home/fabien/.julia/packages/SpecialFunctions/qmwwl/src/erf.jl:342
