Revert of `DropConstant` assumes same number of rows
MWE:

```julia
julia> d = georef((a=1:3, b=fill(1,3)))
3×3 GeoTable over 3 CartesianGrid{1,Float64}
┌─────────────┬─────────────┬─────────────────────────┐
│      a      │      b      │        geometry         │
│ Categorical │ Categorical │         Segment         │
│  [NoUnits]  │  [NoUnits]  │                         │
├─────────────┼─────────────┼─────────────────────────┤
│      1      │      1      │ Segment((0.0,), (1.0,)) │
│      2      │      1      │ Segment((1.0,), (2.0,)) │
│      3      │      1      │ Segment((2.0,), (3.0,)) │
└─────────────┴─────────────┴─────────────────────────┘

julia> n, c = apply(DropConstant(), d)
(3×2 GeoTable over 3 CartesianGrid{1,Float64}, ((Select([:a], nothing), ([:a], [1], [:b], [[1, 1, 1]], Union{Nothing, Int64}[2])), nothing))

julia> nn = georef((a=1:6,))
6×2 GeoTable over 6 CartesianGrid{1,Float64}
┌─────────────┬─────────────────────────┐
│      a      │        geometry         │
│ Categorical │         Segment         │
│  [NoUnits]  │                         │
├─────────────┼─────────────────────────┤
│      1      │ Segment((0.0,), (1.0,)) │
│      2      │ Segment((1.0,), (2.0,)) │
│      3      │ Segment((2.0,), (3.0,)) │
│      4      │ Segment((3.0,), (4.0,)) │
│      5      │ Segment((4.0,), (5.0,)) │
│      6      │ Segment((5.0,), (6.0,)) │
└─────────────┴─────────────────────────┘

julia> revert(DropConstant(), nn, c)
Error showing value of type GeoTable{CartesianGrid{1, Float64}, NamedTuple{(:a, :b), Tuple{UnitRange{Int64}, Vector{Int64}}}}:
ERROR: BoundsError: attempt to access 3-element Vector{Int64} at index [4]
```
