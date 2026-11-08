Dealing with microseconds
R permits fractional seconds in POSIXct objects, seemingly to arbitrary accuracy. But DateTime only goes to millisecond accuracy.

```
julia> using RCall

julia> rcopy(R"as.POSIXct('2020-10-09 12:09:46.123')")
2020-10-09T11:09:46.123

julia> rcopy(R"as.POSIXct('2020-10-09 12:09:46.123456789')")
ERROR: InexactError: Int64(6.373792498612346e13)
Stacktrace:
 [1] Int64 at ./float.jl:710 [inlined]
 [2] convert at ./number.jl:7 [inlined]
 [3] Millisecond at /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.5/Dates/src/types.jl:33 [inlined]
 [4] rcopy at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/convert/datetime.jl:9 [inlined]
 [5] rcopy(::Type{Dates.DateTime}, ::Ptr{RealSxp}) at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/convert/datetime.jl:6
 [6] rcopy(::Ptr{RealSxp}; kwargs::Base.Iterators.Pairs{Union{},Union{},Tuple{},NamedTuple{,Tuple{}}}) at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/convert/default.jl:14
 [7] rcopy at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/convert/default.jl:9 [inlined]
 [8] #rcopy#24 at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/convert/default.jl:6 [inlined]
 [9] rcopy(::RObject{RealSxp}) at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/convert/default.jl:6
 [10] top-level scope at /Users/sthomas/.julia/packages/RCall/AEOQ7/src/macros.jl:71
```

I work with timestamps from BigQuery that have microsecond accuracy, so I can't get the results from a query without hitting that error.

Is there a way to tell RCall to truncate to the accuracy of the DateTime type when converting? I don't actually need the microseconds, I just want the data to fit into a DateTime.
