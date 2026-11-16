Lake module: with small lakes and/or dry conditions simulation fails
### Wflow version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have checked that this bug exists on the latest version of Wflow.


### Reproducible Example

For a large catchment (Pantanal) with many (small) lakes an error is thrown from the Lake module after running the simulation for ~4 years:

```
┌ Error: Wflow simulation failed
│   exception =
│    DomainError with -9.313225746154785e-10:
│    log will only return a complex result if called with a complex argument. Try log(Complex(x)).
│    Stacktrace:
│      [1] throw_complex_domainerror(f::Symbol, x::Float64)
│        @ Base.Math .\math.jl:33
│      [2] _log(x::Float64, base::Val{:ℯ}, func::Symbol)
│        @ Base.Math .\special\log.jl:301
│      [3] log
│        @ .\special\log.jl:267 [inlined]
│      [4] pow
│        @ C:\Users\wcp_w2209251\.julia\packages\Wflow\MvUdN\src\utils.jl:417 [inlined]
│      [5] update(lake::Wflow.Lake{Float64}, i::Int64, inflow::Float64, doy::Int64, timestepsecs::Float64)
│        @ Wflow C:\Users\wcp_w2209251\.julia\packages\Wflow\MvUdN\src\reservoir_lake.jl:513
```

### Current behaviour

It seems the sum of the terms in the quadratic solution (Modified Puls approach) can get negative, causing this error.

### Desired behaviour

The sum of the terms in the quadratic solution of the Lake module should always be positive. Probably, before solving the quadratic equation, a check of the lake balance terms is required.

### Additional Context

_No response_
