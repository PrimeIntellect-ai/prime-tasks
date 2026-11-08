Bug in DenseAxisArrayView
`DenseAxisArrayView` does not eliminate one-element axis correctly.

```julia
julia> y = Containers.@container([i = 1:3, j = 1:2], (i, j))
3×2 Matrix{Tuple{Int64, Int64}}:
 (1, 1)  (1, 2)
 (2, 1)  (2, 2)
 (3, 1)  (3, 2)

julia> x = Containers.@container([i = 4:6, j = [:A, :B]], (i, j))
2-dimensional DenseAxisArray{Tuple{Int64, Symbol},2,...} with index sets:
    Dimension 1, 4:6
    Dimension 2, [:A, :B]
And data, a 3×2 Matrix{Tuple{Int64, Symbol}}:
 (4, :A)  (4, :B)
 (5, :A)  (5, :B)
 (6, :A)  (6, :B)

julia> axes(@view y[2:3, 2])
(Base.OneTo(2),)

julia> axes(@view x[5:6, :A])
(5:6, :A)

julia> @view x[5:6, :A]
Error showing value of type JuMP.Containers.DenseAxisArrayView{Tuple{Int64, Symbol}, 2, JuMP.Containers.DenseAxisArray{Tuple{Int64, Symbol}, 2, Tuple{UnitRange{Int64}, Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Tuple{Int64, Int64}}, JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, Tuple{UnitRange{Int64}, Symbol}}:
ERROR: MethodError: no method matching length(::Symbol)
Closest candidates are:
  length(::Union{Base.KeySet, Base.ValueIterator}) at abstractdict.jl:58
  length(::Union{DataStructures.OrderedRobinDict, DataStructures.RobinDict}) at C:\Users\yangyue\.julia\packages\DataStructures\59MD0\src\ordered_robin_dict.jl:86
  length(::Union{DataStructures.SortedDict, DataStructures.SortedMultiDict, DataStructures.SortedSet}) at C:\Users\yangyue\.julia\packages\DataStructures\59MD0\src\container_loops.jl:322
  ...
Stacktrace:
  [1] _broadcast_getindex_evalf
    @ .\broadcast.jl:670 [inlined]
  [2] _broadcast_getindex
    @ .\broadcast.jl:643 [inlined]
  [3] (::Base.Broadcast.var"#29#30"{Base.Broadcast.Broadcasted{Base.Broadcast.Style{Tuple}, Nothing, typeof(length), Tuple{Tuple{UnitRange{Int64}, Symbol}}}})(k::Int64)
    @ Base.Broadcast .\broadcast.jl:1075
  [4] ntuple
    @ .\ntuple.jl:49 [inlined]
  [5] copy
    @ .\broadcast.jl:1075 [inlined]
  [6] materialize
    @ .\broadcast.jl:860 [inlined]
  [7] size(x::JuMP.Containers.DenseAxisArrayView{Tuple{Int64, Symbol}, 2, JuMP.Containers.DenseAxisArray{Tuple{Int64, Symbol}, 2, Tuple{UnitRange{Int64}, Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Tuple{Int64, Int64}}, JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, Tuple{UnitRange{Int64}, Symbol}})
    @ JuMP.Containers C:\Users\yangyue\.julia\packages\JuMP\cTtPj\src\Containers\DenseAxisArray.jl:642
  [8] length
    @ .\abstractarray.jl:279 [inlined]
  [9] isempty(a::JuMP.Containers.DenseAxisArrayView{Tuple{Int64, Symbol}, 2, JuMP.Containers.DenseAxisArray{Tuple{Int64, Symbol}, 2, Tuple{UnitRange{Int64}, Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Tuple{Int64, Int64}}, JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, Tuple{UnitRange{Int64}, Symbol}})
    @ Base .\abstractarray.jl:1170
 [10] show(io::IOContext{Base.TTY}, #unused#::MIME{Symbol("text/plain")}, X::JuMP.Containers.DenseAxisArrayView{Tuple{Int64, Symbol}, 2, JuMP.Containers.DenseAxisArray{Tuple{Int64, Symbol}, 2, Tuple{UnitRange{Int64}, Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Tuple{Int64, Int64}}, JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, Tuple{UnitRange{Int64}, Symbol}})
    @ Base .\arrayshow.jl:364
 [11] (::REPL.var"#43#44"{REPL.REPLDisplay{REPL.LineEditREPL}, MIME{Symbol("text/plain")}, Base.RefValue{Any}})(io::Any)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:267
 [12] with_repl_linfo(f::Any, repl::REPL.LineEditREPL)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:521
 [13] display(d::REPL.REPLDisplay, mime::MIME{Symbol("text/plain")}, x::Any)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:260
 [14] display(d::REPL.REPLDisplay, x::Any)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:272
 [15] display(x::Any)
    @ Base.Multimedia .\multimedia.jl:328
 [16] #invokelatest#2
    @ .\essentials.jl:729 [inlined]
 [17] invokelatest
    @ .\essentials.jl:726 [inlined]
 [18] print_response(errio::IO, response::Any, show_value::Bool, have_color::Bool, specialdisplay::Union{Nothing, AbstractDisplay})
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:296
 [19] (::REPL.var"#45#46"{REPL.LineEditREPL, Pair{Any, Bool}, Bool, Bool})(io::Any)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:278
 [20] with_repl_linfo(f::Any, repl::REPL.LineEditREPL)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:521
 [21] print_response(repl::REPL.AbstractREPL, response::Any, show_value::Bool, have_color::Bool)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:276
 [22] (::REPL.var"#do_respond#66"{Bool, Bool, REPL.var"#77#87"{REPL.LineEditREPL, REPL.REPLHistoryProvider}, REPL.LineEditREPL, REPL.LineEdit.Prompt})(s::REPL.LineEdit.MIState, buf::Any, ok::Bool)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:857
 [23] #invokelatest#2
    @ .\essentials.jl:729 [inlined]
 [24] invokelatest
    @ .\essentials.jl:726 [inlined]
 [25] run_interface(terminal::REPL.Terminals.TextTerminal, m::REPL.LineEdit.ModalInterface, s::REPL.LineEdit.MIState)
    @ REPL.LineEdit C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\LineEdit.jl:2510
 [26] run_frontend(repl::REPL.LineEditREPL, backend::REPL.REPLBackendRef)
    @ REPL C:\Users\yangyue\AppData\Local\Programs\Julia-1.8.4\share\julia\stdlib\v1.8\REPL\src\REPL.jl:1248
 [27] (::REPL.var"#49#54"{REPL.LineEditREPL, REPL.REPLBackendRef})()
    @ REPL .\task.jl:484
```

As a side note, when reading the code of `DenseAxisArrayView`, I think it is very similar to `DenseAxisArray` and we must duplicate the same functions for it if we want to make it like a real `DenseAxisArray`.

Maybe a better approach is to add a boolean switch `is_view` based on `DenseAxisArray`? (As a generic type parameter or a new field)
