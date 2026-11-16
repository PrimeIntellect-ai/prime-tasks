Can't read CSV with unix timestamp
Julia 1.3.1

```Julia
using TimeSeries;

candles = readtimearray("./dataset/data/data.csv");
```

```Julia
ERROR: LoadError: BoundsError: attempt to access 0-element Array{Float64,1} at index [1]
Stacktrace:
 [1] getindex(::Array{Float64,1}, ::Int64) at .\array.jl:744
 [2] #readtimearray#54(::Char, ::Nothing, ::String, ::Bool, ::typeof(readtimearray), ::String) at C:\Users\SEnergy\.julia\packages\TimeSeries\8Z5Is\src\readwrite.jl:15
 [3] readtimearray(::String) at C:\Users\SEnergy\.julia\packages\TimeSeries\8Z5Is\src\readwrite.jl:5
 [4] top-level scope at d:\OneDrive\Dev\datatest\stupidshit.jl:3
 [5] include at .\boot.jl:328 [inlined]
 [6] include_relative(::Module, ::String) at .\loading.jl:1105
 [7] include(::Module, ::String) at .\Base.jl:31
 [8] include(::String) at .\client.jl:424
 [9] top-level scope at REPL[3]:1
```

loading using CSV:
```Julia
using CSV, TimeSeries;

TimeArray(CSV.File("./dataset/data/data.csv"), timestamp = :date)
```
```Julia
ERROR: LoadError: MethodError: no method matching TimeArray(::Array{Int64,1}, ::Array{Float64,2}, ::Array{Symbol,1}, ::CSV.File{false})
Closest candidates are:
  TimeArray(::AbstractArray{D,1}, ::AbstractArray{T,N}, ::Array{Symbol,1}, ::Any; args...) where {T, N, D<:TimeType} at C:\Users\SEnergy\.julia\packages\TimeSeries\8Z5Is\src\timearray.jl:89
  TimeArray(::D, ::AbstractArray{T,N}, ::Array{Symbol,1}, ::Any; args...) where {T, N, D<:TimeType} at C:\Users\SEnergy\.julia\packages\TimeSeries\8Z5Is\src\timearray.jl:94
  TimeArray(::AbstractArray{D,1}, ::AbstractArray{T,N}, ::Array{Symbol,1}) where {T, N, D<:TimeType} at C:\Users\SEnergy\.julia\packages\TimeSeries\8Z5Is\src\timearray.jl:89
  ...
Stacktrace:
 [1] #TimeArray#3(::Symbol, ::Type{TimeArray}, ::CSV.File{false}) at C:\Users\SEnergy\.julia\packages\TimeSeries\8Z5Is\src\tables.jl:70
 [2] (::Core.var"#kw#Type")(::NamedTuple{(:timestamp,),Tuple{Symbol}}, ::Type{TimeArray}, ::CSV.File{false}) at .\none:0
 [3] top-level scope at d:\OneDrive\Dev\datatest\stupidshit.jl:3
 [4] include at .\boot.jl:328 [inlined]
 [5] include_relative(::Module, ::String) at .\loading.jl:1105
 [6] include(::Module, ::String) at .\Base.jl:31
 [7] include(::String) at .\client.jl:424
 [8] top-level scope at REPL[1]:1
```

the file contains data as follows:

> date,high,low,open,close,volume,quoteVolume,weightedAverage
> 1438992000,50.0,0.00262,50.0,0.00312499,1205.80332085,266206.08039703,0.00452958
> 1439078400,0.0041,0.0024,0.00299999,0.00258069,898.12343401,313987.87486089,0.00286037
> 1439164800,0.0029022,0.0022,0.00264996,0.00264498,718.36526568,284575.40630873,0.00252434
> 1439251200,0.0044,0.002414,0.00264959,0.00395009,3007.27411094,915138.49590874,0.00328614

I've been stuck on this for past 2 hours and it's driving me mad, nothing works to read these data... I can read them with CSV package, but then I can't convert it to TimeArray for plotting

### Additional contract requirements

- `TimeArray(x; timestamp::Symbol, timeparser::Callable = identity)` must support constructing a `TimeArray` from tabular data with a timestamp column stored as Unix-epoch seconds. Apply `timeparser` element-wise to that column before using its values as timestamps; for example, `Date ∘ unix2datetime` converts Unix-epoch seconds to dates. Use the other table columns as the `TimeArray` values.
