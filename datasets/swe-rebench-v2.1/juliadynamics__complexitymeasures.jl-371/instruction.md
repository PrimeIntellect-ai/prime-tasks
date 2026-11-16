`eachindex` for `Probabilities` is ambiguous
While working for a fix for #368, I encountered this (on ComplexityMeasures v3.0.2, Julia 1.9.4):

```julia
julia> using ComplexityMeasures

julia> s = StatisticalComplexity(def = ShannonExtropy(), o = Dispersion(), pest = Shrinkage())
StatisticalComplexity{Distances.JSDivergence, Shrinkage{Nothing, Nothing}, Dispersion{GaussianCDFEncoding}, ShannonExtropy{Int64}}(Distances.JSDivergence(), ShannonExtropy{Int64}(2), Shrinkage{Nothing, Nothing}(nothing, nothing), Dispersion{GaussianCDFEncoding}(GaussianCDFEncoding, 3, 2, 1, false), Base.RefValue{Float64}(0.0))

julia> entropy_complexity_curves(s)
ERROR: MethodError: eachindex(::Probabilities{Float64, 1, Symbol}) is ambiguous.

Candidates:
  eachindex(A::AbstractArray, B::AbstractArray...)
    @ Base abstractarray.jl:377
  eachindex(d::Probabilities{T, N}, args...) where {T, N}
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/core/probabilities.jl:97
  eachindex(A::AbstractVector)
    @ Base abstractarray.jl:314
  eachindex(A::AbstractArray)
    @ Base abstractarray.jl:371

[HIDDEN]

Stacktrace:
  [1] first(a::Probabilities{Float64, 1, Symbol})
    @ Base ./abstractarray.jl:445
  [2] _mean(f::typeof(identity), A::Probabilities{Float64, 1, Symbol}, dims::Colon)
    @ Statistics /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:176
  [3] #mean#2
    @ /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:164 [inlined]
  [4] mean
    @ /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:164 [inlined]
  [5] _var(A::Probabilities{Float64, 1, Symbol}, corrected::Bool, mean::Nothing, #unused#::Colon)
    @ Statistics /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:379
  [6] #var#15
    @ /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:368 [inlined]
  [7] var
    @ /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:368 [inlined]
  [8] _std(A::Probabilities{Float64, 1, Symbol}, corrected::Bool, mean::Nothing, #unused#::Colon)
    @ Statistics /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:460
  [9] #std#17
    @ /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:449 [inlined]
 [10] std
    @ /Applications/Julia-1.9.app/Contents/Resources/julia/share/julia/stdlib/v1.9/Statistics/src/Statistics.jl:449 [inlined]
 [11] codify(est::Dispersion{GaussianCDFEncoding}, x::Probabilities{Float64, 1, Symbol})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/outcome_spaces/dispersion.jl:101
 [12] counts_and_outcomes(o::Dispersion{GaussianCDFEncoding}, x::Probabilities{Float64, 1, Symbol})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/outcome_spaces/dispersion.jl:75
 [13] probabilities_and_outcomes(est::RelativeAmount, outcomemodel::Dispersion{GaussianCDFEncoding}, x::Probabilities{Float64, 1, Symbol})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/probabilities_estimators/RelativeAmount.jl:53
 [14] probabilities_and_outcomes(est::Shrinkage{Nothing, Nothing}, outcomemodel::Dispersion{GaussianCDFEncoding}, x::Probabilities{Float64, 1, Symbol})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/probabilities_estimators/Shrinkage.jl:65
 [15] probabilities
    @ ~/Documents/Repos/ComplexityMeasures.jl/src/core/probabilities.jl:272 [inlined]
 [16] information(hest::PlugIn{ShannonExtropy{Int64}}, pest::Shrinkage{Nothing, Nothing}, o::Dispersion{GaussianCDFEncoding}, x::Probabilities{Float64, 1, Symbol})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/discrete_info_estimators/plugin.jl:38
 [17] information
    @ ~/Documents/Repos/ComplexityMeasures.jl/src/core/information_functions.jl:99 [inlined]
 [18] complexity(c::StatisticalComplexity{Distances.JSDivergence, Shrinkage{Nothing, Nothing}, Dispersion{GaussianCDFEncoding}, ShannonExtropy{Int64}}, p::Probabilities{Float64, 1, Symbol})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/complexity_measures/statistical_complexity.jl:114
 [19] entropy_complexity_curves(c::StatisticalComplexity{Distances.JSDivergence, Shrinkage{Nothing, Nothing}, Dispersion{GaussianCDFEncoding}, ShannonExtropy{Int64}}; num_max::Int64, num_min::Int64)
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/complexity_measures/statistical_complexity.jl:173
 [20] entropy_complexity_curves(c::StatisticalComplexity{Distances.JSDivergence, Shrinkage{Nothing, Nothing}, Dispersion{GaussianCDFEncoding}, ShannonExtropy{Int64}})
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/complexity_measures/statistical_complexity.jl:157
 [21] top-level scope
    @ REPL[22]:1

```

It turns out this has nothing to do with the statistical complexity:

```julia
julia> p = probabilities(RelativeAmount(), Dispersion(), rand(50))
 Probabilities{Float64,1} over 9 outcomes
 [1, 1]  0.14285714285714285
 [1, 2]  0.08163265306122448
 [1, 3]  0.14285714285714285
 [2, 1]  0.14285714285714285
 [2, 2]  0.061224489795918366
 [2, 3]  0.061224489795918366
 [3, 1]  0.10204081632653061
 [3, 2]  0.10204081632653061
 [3, 3]  0.16326530612244897

julia> eachindex(p)
ERROR: MethodError: eachindex(::Probabilities{Float64, 1, Symbol}) is ambiguous.

Candidates:
  eachindex(A::AbstractArray, B::AbstractArray...)
    @ Base abstractarray.jl:377
  eachindex(d::Probabilities{T, N}, args...) where {T, N}
    @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/core/probabilities.jl:97
  eachindex(A::AbstractVector)
    @ Base abstractarray.jl:314
  eachindex(A::AbstractArray)
    @ Base abstractarray.jl:371

[HIDDEN]

Stacktrace:
 [1] top-level scope
   @ REPL[19]:1
```
