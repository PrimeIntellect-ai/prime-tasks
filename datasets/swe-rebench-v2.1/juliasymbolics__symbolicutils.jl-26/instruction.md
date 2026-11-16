Rules not being reached
```julia
julia> using SymbolicUtils

julia> @vars x
(x,)

julia> simplify(1x + 3x)
((3 * x) + x)

julia> SymbolicUtils.SIMPLIFY_RULES[11](1x + 3x)
(4 * x)
```
At first I thought this might have been caused by my recent modification to `RuleSet`, but I checked out an old commit and that was not the problem.
