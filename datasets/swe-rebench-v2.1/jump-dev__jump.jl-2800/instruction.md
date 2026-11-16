LoadError after updating from version 0.21.10 to 0.22.0
I am using code that runs fine with JuMP version 0.21.10. After updating to version 0.22.0 I get the following LoadError:

```
ERROR: LoadError: LoadError: LoadError: [HIDDEN]
Closest candidates are:
  _depends_on(::Expr, ::Symbol) at C:\Users\mopoo\.julia\packages\JuMP\yP8fy\src\Containers\macro.jl:159
  _depends_on(::Any, ::Symbol) at C:\Users\mopoo\.julia\packages\JuMP\yP8fy\src\Containers\macro.jl:164
Stacktrace:
 [1] _has_dependent_sets(index_vars::Vector{Any}, index_sets::Vector{Any})
   @ JuMP.Containers C:\Users\mopoo\.julia\packages\JuMP\yP8fy\src\Containers\macro.jl:169
 [2] build_ref_sets(_error::JuMP.var"#_error#90"{Tuple{Symbol, Expr, Expr}, Symbol, LineNumberNode}, expr::Expr)
   @ JuMP.Containers C:\Users\mopoo\.julia\packages\JuMP\yP8fy\src\Containers\macro.jl:219
 [3] _constraint_macro(args::Tuple{Symbol, Expr, Expr}, macro_name::Symbol, parsefun::typeof(parse_constraint), source::LineNumberNode)
   @ JuMP C:\Users\mopoo\.julia\packages\JuMP\yP8fy\src\macros.jl:794
 [4] var"@constraint"(__source__::LineNumberNode, __module__::Module, args::Vararg{Any, N} where N)
   @ JuMP C:\Users\mopoo\.julia\packages\JuMP\yP8fy\src\macros.jl:905
 [5] include(fname::String)
   @ Base.MainInclude .\client.jl:444
 [6] top-level scope
   @ c:\Users\mopoo\Projekte\mop_models\runme_opt08.jl:17
in expression starting at c:\Users\mopoo\Projekte\mop_models\time_expanded_model\mip_models.jl:333
in expression starting at c:\Users\mopoo\Projekte\mop_models\time_expanded_model\mip_models.jl:307
in expression starting at c:\Users\mopoo\Projekte\mop_models\runme_opt08.jl:17
```

The macro that provokes the error seems to be (mip_models.jl:333):
```
@constraint(m, clearance[(s1, s2) in clearance_sets, t in 0:T-1],
            bOff[s1,t] + sum( bOn[s2, modT(GT, t+i)] for i = 0:clearance_steps(GT, s1, s2)-1 ) <= 1
        )
```
where modT(..) and clearance_steps(..) return integers. bOff and bOn are variables.

The project is quite big, but if required I can try to provide a minimal example. Thanks for your support!

### Additional contract requirements

- An indexed constraint whose index set supplies tuples and whose subsequent index is a range must be accepted by `@constraint` and expand and evaluate without the reported method error.
