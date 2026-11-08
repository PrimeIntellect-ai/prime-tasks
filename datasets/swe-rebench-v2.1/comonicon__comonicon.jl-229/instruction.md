[BUG] Using optional optional types from Configurations fails with an error.
**Describe the bug**
Using optional optional [types from Configurations](https://comonicon.org/stable/conventions/#Working-with-option-types-from-Configurations) fails with an error.

**Version of the package:**
1.0.0, julia 1.8.3

**To Reproduce**
```julia
module M

using Comonicon
using Configurations

@option struct Opts
    x::String = "x"
end

"""
# Options
- `-c, --config <path/to/option/or/specific field>`: config.
"""
@main function main(;config::Opts=Opts())
    @show config
end

end

M.command_main()
```
> ERROR: KeyError: key :config not found
Stacktrace:
 [1] getindex(h::Dict{Symbol, Any}, key::Symbol)
   @ Base ./dict.jl:498
 [2] command_main(ARGS::Vector{String})
   @ Main.M ~/.julia/dev/Comonicon/src/codegen/julia.jl:277
 [3] command_main()
   @ Main.M ~/.julia/dev/Comonicon/src/codegen/julia.jl:90
 [4] top-level scope
   @ REPL[2]:1

**Expected behavior**
The function should show `config = Main.M.Opts("x")`

**Reason**
[HIDDEN]
