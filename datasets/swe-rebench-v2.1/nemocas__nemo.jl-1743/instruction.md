RealField constructor without precision
https://nemocas.github.io/Nemo.jl/latest/real/#Real-ball-constructors

RR = RealField()

c = RR(1, precision = 100)
d = RR(1//2, precision = 4)

Return:

MethodError: no method matching (::RealField)(::Int64; precision::Int64)

(Julia 1.9.0; Nemo v0.34.2)
