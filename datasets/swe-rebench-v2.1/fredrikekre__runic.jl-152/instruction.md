Failed to format input file.
I ran into an issue formatting a file in https://github.com/QuantumKitHub/MPSKit.jl/pull/303/
I managed to make the following minimal example, with stacktrace:

```
ERROR: failed to format input from runic_file.jl: Runic.AssertionError: re-parsing the formatted output failed. This is unexpected, please file an issue with a reproducible example at https://github.com/fredrikekre/Runic.jl/issues/new.
Stacktrace:
 [1] format_tree!(ctx::Runic.Context)
   @ Runic ~/.julia/packages/Runic/iGXsf/src/Runic.jl:618
 [2] main(argv::Vector{String})
   @ Runic ~/.julia/packages/Runic/iGXsf/src/main.jl:415
 [3] top-level scope
   @ none:1
 [4] eval
   @ ./boot.jl:430 [inlined]
 [5] exec_options(opts::Base.JLOptions)
   @ Base ./client.jl:296
```

```julia
function kitaev_model()
    return Iterators.flatten((((i, i + 1) => TB + SC for i in 1:(L - 1)),
                              (i,) => CP for i in 1:L))
end
```

Note that the following does work:

```julia
function kitaev_model()
    return Iterators.flatten((((i, i + 1) => TB + SC for i in 1:(L - 1)), (i,) => CP for i in 1:L))
end
```
