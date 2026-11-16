Non-explicit index placed without warning
I wanted to raise an un-intuitive behaviour when mistakenly leaving off an index of a variable in a constraint definition. The first value of the missing index's set is implicitly added, and the user is not warned that this has happened.

This has already been raised in first in #653 and again in #937, where it was referred to the upstream discussion at JuliaLang/julia#14770.
I wonder if the loop here has been closed back to JuMP?

Minimal reproducible example(s):
```julia
using JuMP
Arcs = 1:2; Time = 1:2;
m = Model(); @variable(m, flow[Arcs,Time]);
@constraint(m, FlowBound[a=Arcs,t=Time], flow[a] <= 10);
```
we create 6 constraints
```julia
FlowBound[1,1] : flow[1,1] ≤ 10.0      FlowBound[1,2] : flow[1,1] ≤ 10.0
FlowBound[2,1] : flow[2,1] ≤ 10.0     FlowBound[2,2] : flow[2,1] ≤ 10.0
```

The (easy enough to do) lapse was not adding `t` to the indexing of `flow` in the constraint to get the correct constraints for all combinations of `Arcs` and `Time`:
`FlowBound[1,1] : flow[1,1] ≤ 10.0  FlowBound[1,2] : flow[1,2] ≤ 10.0`
 `FlowBound[2,1] : flow[2,1] ≤ 10.0  FlowBound[2,2] : flow[2,2] ≤ 10.0`

This occurs regardless other the elements used in the sets e.g.
`Arcs = [("a","b"), ("a","c"), ("b","c")]; Time = [:x,:y,:z];`

### Additional contract requirements

- Indexing a `DenseAxisArray` or a `SparseAxisArray` with fewer indices than its number of dimensions must throw a `BoundsError` instead of silently dropping dimensions. This applies both to reading an element (`A[i]`) and to assigning one (`A[i] = v`).
- `Base.summary(io, A::DenseAxisArray)` must write a description of `A` to `io`: a first line `N-dimensional DenseAxisArray{T,N,...} with index sets:`, then one line `    Dimension i, <index set>` for each dimension `i`, then a final line `And data, a <summary of the underlying data array>`.
- `Base.summary(io, sa::SparseAxisArray)` must write the concrete type of `sa` followed by ` with N entries` (or ` with 1 entry` when there is exactly one entry).
