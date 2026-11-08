NegativeBinomial wrong mgf
The moment generating function of NegativeBinomial is wrong:
```julia
julia> using Revise, Distributions, ForwardDiff, Test

julia> d = NegativeBinomial(4, 0.2)
NegativeBinomial{Float64}(r=4.0, p=0.2)

julia> @test ForwardDiff.derivative(Base.Fix1(mgf, d), 0) ≈ mean(d)
Test Failed at REPL[3]:1
  Expression: ForwardDiff.derivative(Base.Fix1(mgf, d), 0) ≈ mean(d)
   Evaluated: 5.000000000000001 ≈ 16.0
```
From the code it seems that the implementation of the mgf confuses success and fail probability.
