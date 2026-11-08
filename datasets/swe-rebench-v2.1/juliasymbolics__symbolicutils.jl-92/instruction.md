Error in symbolic functions with more than 2 arguments
The recursion in `promote_symtype` appears to cause an error when calling a symbolic function with more than 2 arguments.
```julia
julia> @syms f(a,b,c)
(f(::Number, ::Number, ::Number)::Number,)

julia> f(1,2,3)
ERROR: f(::Number, ::Number, ::Number)::Number takes 3 arguments; 2 arguments given
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] promote_symtype(::SymbolicUtils.Sym{SymbolicUtils.FnType{Tuple{Number,Number,Number},Number}}, ::Type{T} where T, ::Type{T} where T) at /home/david/.julia/packages/SymbolicUtils/Jm3HG/src/types.jl:166
 [3] rec_promote_symtype(::SymbolicUtils.Sym{SymbolicUtils.FnType{Tuple{Number,Number,Number},Number}}, ::Type{T} where T, ::Type{T} where T, ::Type{T} where T) at /home/david/.julia/packages/SymbolicUtils/Jm3HG/src/methods.jl:35
 [4] term(::SymbolicUtils.Sym{SymbolicUtils.FnType{Tuple{Number,Number,Number},Number}}, ::Int64, ::Vararg{Int64,N} where N; type::Nothing) at /home/david/.julia/packages/SymbolicUtils/Jm3HG/src/types.jl:290
 [5] term(::SymbolicUtils.Sym{SymbolicUtils.FnType{Tuple{Number,Number,Number},Number}}, ::Int64, ::Vararg{Int64,N} where N) at /home/david/.julia/packages/SymbolicUtils/Jm3HG/src/types.jl:289
 [6] (::SymbolicUtils.Sym{SymbolicUtils.FnType{Tuple{Number,Number,Number},Number}})(::Int64, ::Vararg{Int64,N} where N) at /home/david/.julia/packages/SymbolicUtils/Jm3HG/src/types.jl:147
 [7] top-level scope at REPL[3]:1

julia> term(f, 1,2,3; type=Number)
f(1, 2, 3)
```
