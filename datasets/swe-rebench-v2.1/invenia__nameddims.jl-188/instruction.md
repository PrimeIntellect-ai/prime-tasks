Type instability when broadcasting
I was trying to chase down allocations that appeared in my code when converting from `Array` to `NamedDimsArray`. I think I have found a case where we may be failing to get type-stable code. Here is what I think is a minimal example:
```
julia> using NamedDims, BenchmarkTools

julia> function example(a,b,c,d)
           @. a -= 0.5 * d * b * c
           return a
       end
example (generic function with 1 method)

julia> a = NamedDimsArray{(:z,)}(rand(5));

julia> b = NamedDimsArray{(:z,)}(rand(5));

julia> c = rand();

julia> d = rand();

julia> @btime example($a,$b,$c,$d)
  733.862 ns (10 allocations: 352 bytes)
5-element NamedDimsArray{(:z,), Float64, 1, Vector{Float64}}:
 -1085.0390848895406
 -3944.198097644197
 -4564.398164918389
 -3641.011715928582
 -5293.772958207846
```
Using `Cthulhu.@descend` suggests that the problem is [HIDDEN] here
https://github.com/invenia/NamedDims.jl/blob/2fa07ee7d94f34767db849942828f97ba0232b28/src/broadcasting.jl#L68-L80
even though when I then step into `broadcasted_names()`, the return type is `Core.Const((:z,))`!

I think the example is minimal, because if I remove even the `0.5 *` from `example()`, `@btime` reports zero allocations.

I was using julia-1.6.4 and NamedDims-0.2.41. Any suggestions for fixes or further debugging very welcome!

### Additional contract requirements

- The in-place broadcast expression shown in the reproduction should execute without heap allocations for the provided named-array and scalar arguments.
