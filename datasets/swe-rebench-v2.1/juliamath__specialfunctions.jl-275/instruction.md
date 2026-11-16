wrong answer for expint(2.2,3.2)
As mentioned in https://github.com/JuliaMath/SpecialFunctions.jl/pull/273#issuecomment-734063769, there seems to be a bug in `expint` for the abovementioned inputs.

In fact, there is a weird spurious divergence near `ν=2`
```
julia> expint(2,3.2) # correct
0.00833662798044897

julia> expint(2.000001,3.2) # incorrect
3.200002352735261e6
```

It looks like a bug crept in at some point for positive non-integer order?

cc @augustt198
