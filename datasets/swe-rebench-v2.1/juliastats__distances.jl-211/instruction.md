Release 0.10.1 breaking for `allowmissing` arrays
Looks like the latest patch release broke the ability to pass arrays with eltype `Union{<:Real, Missing}`

On 0.10.0:

```julia
julia> using Distances, Missings

julia> nrmsd(allowmissing(rand(10, 4)), rand(10, 4))
0.34261077849743554
```

But on 0.10.1:

```julia
julia> using Distances, Missings

julia> nrmsd(allowmissing(rand(10, 4)), rand(10, 4))
ERROR: MethodError: no method matching oneunit(::Type{Any})
Closest candidates are:
  oneunit(::Type{Union{Missing, T}}) where T at missing.jl:104
  oneunit(::Type{T}) where T at number.jl:300
  oneunit(::T) where T at number.jl:299
  ...
Stacktrace:
 [1] oneunit(::Type{Any}) at ./missing.jl:105
 [2] _eval_start(::SqEuclidean, ::Type{Any}, ::Type{Float64}, ::Nothing) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:320
 [3] _eval_start(::SqEuclidean, ::Type{Any}, ::Type{Float64}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:318
 [4] eval_start(::SqEuclidean, ::Array{Union{Missing, Float64},2}, ::Array{Float64,2}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:317
 [5] _evaluate at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:250 [inlined]
 [6] SqEuclidean at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:328 [inlined]
 [7] sqeuclidean(::Array{Union{Missing, Float64},2}, ::Array{Float64,2}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:353
 [8] (::MeanSqDeviation)(::Array{Union{Missing, Float64},2}, ::Array{Float64,2}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:593
 [9] (::RMSDeviation)(::Array{Union{Missing, Float64},2}, ::Array{Float64,2}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:596
 [10] (::NormRMSDeviation)(::Array{Union{Missing, Float64},2}, ::Array{Float64,2}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:601
 [11] nrmsd(::Array{Union{Missing, Float64},2}, ::Array{Float64,2}) at /Users/rory/.julia/packages/Distances/glUtY/src/metrics.jl:603
 [12] top-level scope at REPL[4]:1
```

I'm not sure if this was intended, but it might be good to push those kinds of changes to a breaking release?
