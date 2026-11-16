New macro calls defining functions are incorrectly revised
Using Revise v3.5.12 and LoweredCodeUtils v2.4.3 on Julia 1.10:

```julia
julia> using Revise

julia> rlogger = Revise.debug_logger();

julia> macro my_macro(name)
           return esc(quote
               function $name end
               println($name)
           end)
       end
@my_macro (macro with 1 method)

julia> file = tempname();

julia> open(file, "w") do f; println(f, "@my_macro f1") end

julia> includet(file); f1
f1
f1 (generic function with 0 methods)

julia> open(file, "a") do f; println(f, "@my_macro f2") end

julia> f2
ERROR: UndefVarError: `f2` not defined

julia> rlogger.logs
1-element Vector{Revise.LogRecord}:
 Revise.LogRecord(Debug, Eval, Action, Revise_9147188b, "C:\Users\lucbr\.julia\packages\Revise
\RZlAf\src\packagedef.jl", 325, (time=1.704399665147e9, deltainfo=(Main, quote
    #= C:\Users\lucbr\AppData\Local\Temp\jl_d2z6zAf8Vk:2 =#
    #= C:\Users\lucbr\AppData\Local\Temp\jl_d2z6zAf8Vk:2 =# @my_macro f2
end)))
```

I was able to replicate the issue with Julia 1.9.
With Revise v3.5.10 and LoweredCodeUtils v2.4.1, `f2` is correctly defined. Using any versions above those results in other errors. The latest ones (v3.5.12 and v2.4.3) are the only one for which it doesn't throw and doesn't work.
