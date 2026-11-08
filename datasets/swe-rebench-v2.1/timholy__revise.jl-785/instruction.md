Wrong directory for include during revision
With this specific set of instructions, after triggering a revision there's an error, because Revise has `include("foo.jl")` look for the file in the current directory (i.e. in `pwd()/foo.jl`) instead of in the path relative to Dummy (`Dummy/src/foo.jl`)

See the `opening file "/Users/cstjean/TestEnv2/foo.jl": No such file or directory` line below, it shows clearly what's wrong.

MWE:

```julia
module Dummy # in Dummy/Dummy.jl
global gvar = true
function f end
include("foo.jl")   # foo.jl is empty (or can contain anything...)
end
```

in fresh environment:

```julia
(TestEnv2) pkg> dev ../Dummy
   Resolving package versions...
    Updating `~/TestEnv2/Project.toml`
  [0defefab] + Dummy v0.0.0 `../Dummy`
    Updating `~/TestEnv2/Manifest.toml`
  [0defefab] + Dummy v0.0.0 `../Dummy`

(TestEnv2) pkg> add Revise
   Resolving package versions...
    Updating `~/TestEnv2/Project.toml`
  [295af30f] + Revise v3.5.3
    Updating `~/TestEnv2/Manifest.toml`
  [da1fd8a2] + CodeTracking v1.3.4
  [aa1ae85d] + JuliaInterpreter v0.9.25
  [6f1432cf] + LoweredCodeUtils v2.3.0
  [bac558e1] + OrderedCollections v1.6.2
  [ae029012] + Requires v1.3.0
  [295af30f] + Revise v3.5.3
  [0dad84c5] + ArgTools v1.1.1
  [56f22d72] + Artifacts
  [2a0f44e3] + Base64
  [ade2ca70] + Dates
  [8ba89e20] + Distributed
  [f43a241f] + Downloads v1.6.0
  [7b1f6079] + FileWatching
  [b77e0a4c] + InteractiveUtils
  [b27032c2] + LibCURL v0.6.3
  [76f85450] + LibGit2
  [8f399da3] + Libdl
  [56ddb016] + Logging
  [d6f4376e] + Markdown
  [ca575930] + NetworkOptions v1.2.0
  [44cfe95a] + Pkg v1.9.2
  [de0858da] + Printf
  [3fa0cd96] + REPL
  [9a3f8284] + Random
  [ea8e919c] + SHA v0.7.0
  [9e88b42a] + Serialization
  [6462fe0b] + Sockets
  [fa267f1f] + TOML v1.0.3
  [a4e569a6] + Tar v1.10.0
  [cf7118a7] + UUIDs
  [4ec0a83e] + Unicode
  [deac9b47] + LibCURL_jll v7.84.0+0
  [29816b5a] + LibSSH2_jll v1.10.2+0
  [c8ffd9c3] + MbedTLS_jll v2.28.2+0
  [14a3606d] + MozillaCACerts_jll v2022.10.11
  [83775a58] + Zlib_jll v1.2.13+0
  [8e850ede] + nghttp2_jll v1.48.0+0
  [3f19e933] + p7zip_jll v17.4.0+0

julia> using Revise, Dummy
# trivially change Dummy.jl
julia> 1
┌ Error: Failed to revise /Users/cstjean/Dummy/src/Dummy.jl
│   exception =
│    SystemError: opening file "/Users/cstjean/TestEnv2/foo.jl": No such file or directory
│    Stacktrace:
│      [1] systemerror(p::String, errno::Int32; extrainfo::Nothing)
│        @ Base error.jl:176
│      [2] kwcall(::NamedTuple{(:extrainfo,), Tuple{Nothing}}, ::typeof(systemerror), p::String, errno::Int32)
│        @ Base error.jl:176
│      [3] kwcall(::NamedTuple{(:extrainfo,), Tuple{Nothing}}, ::typeof(systemerror), p::String)
│        @ Base error.jl:176
│      [4] systemerror(p::String, b::Bool; extrainfo::Nothing)
│        @ Base error.jl:175
│      [5] systemerror(p::String, b::Bool)
│        @ Base error.jl:175
│      [6] open(fname::String; lock::Bool, read::Nothing, write::Nothing, create::Nothing, truncate::Nothing, append::Nothing)
│        @ Base iostream.jl:293
│      [7] open(fname::String)
│        @ Base iostream.jl:275
│      [8] open(f::Base.var"#418#419"{String}, args::Tuple{String}; kwargs::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
│        @ Base io.jl:393
│      [9] open(f::Base.var"#418#419"{String}, args::Tuple{String})
│        @ Base io.jl:392
│     [10] read(filename::String, #unused#::Type{String})
│        @ Base io.jl:473
│     [11] _include(mapexpr::typeof(identity), mod::Module, _path::String)
│        @ Base loading.jl:1959
│     [12] include(mod::Module, _path::String)
│        @ Base Base.jl:457
│     [13] include(x::String)
│        @ Dummy ~/Dummy/src/Dummy.jl:1
│     [14] top-level scope
│        @ ~/Dummy/src/Dummy.jl:4
│    Revise evaluation error at /Users/cstjean/Dummy/src/Dummy.jl:4
```
