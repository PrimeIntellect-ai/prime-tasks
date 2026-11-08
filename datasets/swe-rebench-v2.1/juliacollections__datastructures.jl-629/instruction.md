RobinDict: InexactError is thrown in place of KeyError
```julia
julia> h = RobinDict{Char, Int}()
RobinDict{Char,Int64} with 0 entries

julia> h[0.01]
ERROR: InexactError: UInt32(0.01)
Stacktrace:
 [1] Type at ./float.jl:682 [inlined]
 [2] Type at ./char.jl:48 [inlined]
 [3] convert at ./char.jl:179 [inlined]
 [4] getindex(::RobinDict{Char,Int64}, ::Float64) at /home/ww/.julia/packages/DataStructures/5F6tJ/src/robin_dict.jl:370
 [5] top-level scope at none:0

julia> d = Dict{Char, Int}()
Dict{Char,Int64} with 0 entries

julia> d[0.01]
ERROR: KeyError: key 0.01 not found
Stacktrace:
 [1] getindex(::Dict{Char,Int64}, ::Float64) at ./dict.jl:478
 [2] top-level scope at none:0

```
`RobinDict` should match the behaviour of the `Base.Dict`.
Similar behavior for `haskey`, `getkey`, `get!`
