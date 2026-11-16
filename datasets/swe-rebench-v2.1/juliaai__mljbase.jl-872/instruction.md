`evaluate` errors displaying when using `confusion_matrix` as measure
When using confusion matrix as a measure in `evaluate` or in `evaluate!` I get this error with displaying the aggregated confusion matrix. After checking, I found the result does have the correct confusion matrix. But the full results cannot be displayed, only each individual part separately.

Minimal example

```
using MLJ
import DataFrames

X = DataFrames.DataFrame(
    :x1 => rand(100),
    :x2 => rand(100),
);

y = randn(100) .> 0;
y = coerce(y, OrderedFactor);

@load LogisticClassifier pkg=MLJLinearModels

mdl = MLJLinearModels.LogisticClassifier()
cv = CV(nfolds=5)

@show scitype(X) # Table{AbstractVector{Continuous}}

@show aggregation(confusion_matrix) # StatisticalTraits.Sum()

result = evaluate(mdl, X, y, resampling=cv, measures=confusion_matrix)

result.measurement[1] # does hold the confusion matrix
```

the last line gives this error:
```
ERROR: MethodError: no method matching /(::MLJBase.ConfusionMatrixObject{2}, ::Int64)
Closest candidates are:
  /(::Union{Int128, Int16, Int32, Int64, Int8, UInt128, UInt16, UInt32, UInt64, UInt8}, ::Union{Int128, Int16, Int32, Int64, Int8, UInt128, UInt16, UInt32, UInt64, UInt8}) at int.jl:97
  /(::Union{SparseArrays.SparseVector{Tv, Ti}, SubArray{Tv, 1, <:SparseArrays.AbstractSparseMatrixCSC{Tv, Ti}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, false}, SubArray{Tv, 1, <:SparseArrays.AbstractSparseVector{Tv, Ti}, Tuple{Base.Slice{Base.OneTo{Int64}}}, false}} where {Tv, Ti}, ::Number) at ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/SparseArrays/src/sparsevector.jl:1519
  /(::Union{ColorTypes.LMS, ColorTypes.XYZ}, ::Number) at ~/.julia/packages/Colors/yDxFN/src/algorithms.jl:9
  ...
Stacktrace:
  [1] _mean(f::typeof(identity), A::Vector{MLJBase.ConfusionMatrixObject{2}}, dims::Colon)
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:176
  [2] mean(A::Vector{MLJBase.ConfusionMatrixObject{2}}; dims::Function)
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:164
  [3] mean(A::Vector{MLJBase.ConfusionMatrixObject{2}})
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:164
  [4] _var(A::Vector{MLJBase.ConfusionMatrixObject{2}}, corrected::Bool, mean::Nothing, #unused#::Colon)
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:379
  [5] var(A::Vector{MLJBase.ConfusionMatrixObject{2}}; corrected::Bool, mean::Nothing, dims::Function)
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:368
  [6] _std(A::Vector{MLJBase.ConfusionMatrixObject{2}}, corrected::Bool, mean::Nothing, #unused#::Colon)
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:454
  [7] std(A::Vector{MLJBase.ConfusionMatrixObject{2}}; corrected::Bool, mean::Nothing, dims::Function)
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:449
  [8] std(A::Vector{MLJBase.ConfusionMatrixObject{2}})
    @ Statistics ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/Statistics/src/Statistics.jl:449
  [9] (::MLJBase.var"#291#292"{Int64, Float64})(per_fold::Vector{MLJBase.ConfusionMatrixObject{2}})
    @ MLJBase ~/.julia/packages/MLJBase/LxNAs/src/resampling.jl:543
 [10] iterate
    @ ./generator.jl:47 [inlined]
 [11] _collect
    @ ./array.jl:807 [inlined]
 [12] collect_similar
    @ ./array.jl:716 [inlined]
 [13] map
    @ ./abstractarray.jl:2933 [inlined]
 [14] _standard_errors
    @ ~/.julia/packages/MLJBase/LxNAs/src/resampling.jl:542 [inlined]
 [15] show(io::IOContext{Base.TTY}, #unused#::MIME{Symbol("text/plain")}, e::PerformanceEvaluation{Vector{ConfusionMatrix}, Vector{MLJBase.ConfusionMatrixObject{2}}, Vector{typeof(predict_mode)}, Vector{Vector{MLJBase.ConfusionMatrixObject{2}}}, Vector{Missing}, Vector{NamedTuple{(:classes, :coefs, :intercept), Tuple{CategoricalArrays.CategoricalVector{Bool, UInt32, Bool, CategoricalArrays.CategoricalValue{Bool, UInt32}, Union{}}, Vector{Pair{Symbol, Float64}}, Float64}}}, Vector{Nothing}})
    @ MLJBase ~/.julia/packages/MLJBase/LxNAs/src/resampling.jl:552
 [16] (::REPL.var"#43#44"{REPL.REPLDisplay{REPL.LineEditREPL}, MIME{Symbol("text/plain")}, Base.RefValue{Any}})(io::Any)
    @ REPL ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/REPL/src/REPL.jl:267
 [17] with_repl_linfo(f::Any, repl::REPL.LineEditREPL)
    @ REPL ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/REPL/src/REPL.jl:521
 [18] display(d::REPL.REPLDisplay, mime::MIME{Symbol("text/plain")}, x::Any)
    @ REPL ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/REPL/src/REPL.jl:260
 [19] display(d::REPL.REPLDisplay, x::Any)
    @ REPL ~/.julia/juliaup/julia-1.8.3+0.x64/share/julia/stdlib/v1.8/REPL/src/REPL.jl:272
 [20] display(x::Any)
    @ Base.Multimedia ./multimedia.jl:328
 [21] #invokelatest#2
    @ ./essentials.jl:729 [inlined]
 [22] invokelatest
    @ ./essentials.jl:726 [inlined]
 [23] (::VSCodeServer.var"#66#70"{Bool, Bool, Bool, Module, String, Int64, Int64, String, VSCodeServer.ReplRunCodeRequestParams})()
    @ VSCodeServer ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/eval.jl:199
 [24] withpath(f::VSCodeServer.var"#66#70"{Bool, Bool, Bool, Module, String, Int64, Int64, String, VSCodeServer.ReplRunCodeRequestParams}, path::String)
    @ VSCodeServer ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/repl.jl:249
 [25] (::VSCodeServer.var"#65#69"{Bool, Bool, Bool, Module, String, Int64, Int64, String, VSCodeServer.ReplRunCodeRequestParams})()
    @ VSCodeServer ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/eval.jl:155
 [26] hideprompt(f::VSCodeServer.var"#65#69"{Bool, Bool, Bool, Module, String, Int64, Int64, String, VSCodeServer.ReplRunCodeRequestParams})
    @ VSCodeServer ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/repl.jl:38
 [27] (::VSCodeServer.var"#64#68"{Bool, Bool, Bool, Module, String, Int64, Int64, String, VSCodeServer.ReplRunCodeRequestParams})()
    @ VSCodeServer ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/eval.jl:126
 [28] with_logstate(f::Function, logstate::Any)
    @ Base.CoreLogging ./logging.jl:511
 [29] with_logger
    @ ./logging.jl:623 [inlined]
 [30] (::VSCodeServer.var"#63#67"{VSCodeServer.ReplRunCodeRequestParams})()
    @ VSCodeServer ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/eval.jl:225
 [31] #invokelatest#2
    @ ./essentials.jl:729 [inlined]
 [32] invokelatest(::Any)
    @ Base ./essentials.jl:726
 [33] macro expansion
    @ ~/.vscode/extensions/julialang.language-julia-1.38.2/scripts/packages/VSCodeServer/src/eval.jl:34 [inlined]
 [34] (::VSCodeServer.var"#61#62")()
    @ VSCodeServer ./task.jl:484
```
