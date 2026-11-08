Missing deprecation for `OrdinalPatterns{m}(; τ)`
During the rewrite for 3.0, the keyword `τ` became a positional argument. Therefore, pre-V3 code like the following fails

```julia
julia> m = 3; τ = 2; OrdinalPatterns{m}(; τ)
ERROR: MethodError: no method matching (OrdinalPatterns{3})(; τ::Int64)

Closest candidates are:
  (OrdinalPatterns{m})() where m got unsupported keyword argument "τ"
   @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/outcome_spaces/ordinal_patterns.jl:198
  (OrdinalPatterns{m})(::Int64) where m got unsupported keyword argument "τ"
   @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/outcome_spaces/ordinal_patterns.jl:198
  (OrdinalPatterns{m})(::Int64, ::F) where {m, F} got unsupported keyword argument "τ"
   @ ComplexityMeasures ~/Documents/Repos/ComplexityMeasures.jl/src/outcome_spaces/ordinal_patterns.jl:198

Stacktrace:
 [1] top-level scope
   @ REPL[88]:1
```

Whether this was intentional or not, it needs a deprecation.
