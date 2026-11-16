More gamma_inc_inv Failures
Hello,

The last patch fixed a lot of the issues I was running into with Distributions.jl. However, I was still able to trigger two more (unique) failure cases. When calling via Distributions.jl, I was able to trigger one case with this

```julia
dG = Gamma{Float64}(0.0016546512046778552, 0.21745036229505915)
q = 1-0.7070707070707071
quantile(dG,q)

ERROR: DomainError with -9.5893e-320:
log will only return a complex result if called with a complex argument. Try log(Complex(x)).
Stacktrace:
 [1] throw_complex_domainerror(f::Symbol, x::Float64)
   @ Base.Math .\math.jl:33
 [2] _log(x::Float64, base::Val{:ℯ}, func::Symbol)
   @ Base.Math .\special\log.jl:304
 [3] log
   @ .\special\log.jl:269 [inlined]
 [4] __gamma_inc_inv(a::Float64, minpq::Float64, pcase::Bool)
   @ SpecialFunctions C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:971
 [5] _gamma_inc_inv
   @ C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:935 [inlined]
 [6] gamma_inc_inv
   @ C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:917 [inlined]
 [7] gammainvcdf
   @ C:\Users\usr\.julia\packages\StatsFuns\dTYga\src\distrs\gamma.jl:98 [inlined]
 [8] quantile(d::Gamma{Float64}, q::Float64)
   @ Distributions C:\Users\usr\.julia\packages\Distributions\T2SAc\src\univariates.jl:627
 [9] top-level scope
   @ REPL[4]:1
```
The second failure case was triggered with this:
```julia
dG = Gamma{Float64}(1.0309015068677239, 0.03724188228734454)
q = 1-0.020202020202020204

quantile(dG, q)
ERROR: DomainError with (1.0309015068677239, -380.7187661907244, 0):
`a` and `x` must be greater than 0 ---- Domain : (0, Inf)
Stacktrace:
 [1] _gamma_inc(a::Float64, x::Float64, ind::Int64)
   @ SpecialFunctions C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:787
 [2] gamma_inc
   @ C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:781 [inlined]
 [3] __gamma_inc_inv(a::Float64, minpq::Float64, pcase::Bool)
   @ SpecialFunctions C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:981
 [4] _gamma_inc_inv
   @ C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:935 [inlined]
 [5] gamma_inc_inv
   @ C:\Users\usr\.julia\packages\SpecialFunctions\rNt4H\src\gamma_inc.jl:917 [inlined]
 [6] gammainvcdf
   @ C:\Users\usr\.julia\packages\StatsFuns\dTYga\src\distrs\gamma.jl:98 [inlined]
 [7] quantile(d::Gamma{Float64}, q::Float64)
   @ Distributions C:\Users\usr\.julia\packages\Distributions\T2SAc\src\univariates.jl:627
 [8] top-level scope
   @ REPL[10]:1
   ```
