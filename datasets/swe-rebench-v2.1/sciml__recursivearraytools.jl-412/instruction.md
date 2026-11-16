Broadcasting over `VectorOfArray` does not preserve type of parent array
**Describe the bug 🐞**

Broadcasting a function over `VectorOfArray(::StructArray{SVector})` does not preserve the `StructArray{SVector}` type of the parent array. Instead, it produces `VectorOfArray(::Array{SVector})`

**Expected behavior**

I expect broadcasting over `VectorOfArray(::StructArray{SVector})` to create another `VectorOfArray(::StructArray{SVector})`.

**Minimal Reproducible Example 👇**

```julia
using RecursiveArrayTools, StructArrays, StaticArrays
x = StructArray{SVector{2, Float64}}((randn(2), randn(2)))
typeof(zero.(VectorOfArray(x))) # VectorOfArray{Float64, 2, Vector{SVector{2, Float64}}}
```
I would expect `typeof(zero.(VectorOfArray(x)))` to be the same as `typeof(VectorOfArray)`.

**Environment (please complete the following information):**

  - Output of `using Pkg; Pkg.status()`

```julia
julia> using Pkg; Pkg.status()
Status `/private/var/folders/jz/1v6mxm6s45x5xm3l8dsqbcbr0000gp/T/jl_NAnzZK/Project.toml`
  [731186ca] RecursiveArrayTools v3.27.3
  [90137ffa] StaticArrays v1.9.8
  [09ab397b] StructArrays v0.6.18
```

  - Output of `using Pkg; Pkg.status(; mode = PKGMODE_MANIFEST)`

```julia
julia> using Pkg; Pkg.status(; mode = PKGMODE_MANIFEST)
Status `/private/var/folders/jz/1v6mxm6s45x5xm3l8dsqbcbr0000gp/T/jl_NAnzZK/Manifest.toml`
  [7d9f7c33] Accessors v0.1.38
  [79e6a3ab] Adapt v4.1.1
  [4fba245c] ArrayInterface v7.17.0
  [a33af91c] CompositionsBase v0.1.2
  [187b0558] ConstructionBase v1.5.8
  [9a962f9c] DataAPI v1.16.0
  [e2d170a0] DataValueInterfaces v1.0.0
  [ffbed154] DocStringExtensions v0.9.3
  [e2ba6199] ExprTools v0.1.10
⌃ [46192b85] GPUArraysCore v0.1.6
  [3587e190] InverseFunctions v0.1.17
  [82899510] IteratorInterfaceExtensions v1.0.0
  [1914dd2f] MacroTools v0.5.13
  [bac558e1] OrderedCollections v1.6.3
  [aea7be01] PrecompileTools v1.2.1
  [21216c6a] Preferences v1.4.3
  [3cdcf5f2] RecipesBase v1.3.4
  [731186ca] RecursiveArrayTools v3.27.3
  [ae029012] Requires v1.3.0
  [7e49a35a] RuntimeGeneratedFunctions v0.5.13
  [90137ffa] StaticArrays v1.9.8
  [1e83bf80] StaticArraysCore v1.4.3
  [09ab397b] StructArrays v0.6.18
  [2efcf032] SymbolicIndexingInterface v0.3.35
  [3783bdb8] TableTraits v1.0.1
  [bd369af6] Tables v1.12.0
  [56f22d72] Artifacts
  [2a0f44e3] Base64
  [ade2ca70] Dates
  [76f85450] LibGit2
  [8f399da3] Libdl
  [37e2e46d] LinearAlgebra
  [d6f4376e] Markdown
  [ca575930] NetworkOptions v1.2.0
  [de0858da] Printf
  [9a3f8284] Random
  [ea8e919c] SHA v0.7.0
  [9e88b42a] Serialization
  [2f01184e] SparseArrays v1.10.0
  [10745b16] Statistics v1.10.0
  [fa267f1f] TOML v1.0.3
  [cf7118a7] UUIDs
  [4ec0a83e] Unicode
  [e66e0078] CompilerSupportLibraries_jll v1.1.1+0
  [e37daf67] LibGit2_jll v1.6.4+0
  [29816b5a] LibSSH2_jll v1.11.0+1
  [c8ffd9c3] MbedTLS_jll v2.28.2+1
  [4536629a] OpenBLAS_jll v0.3.23+4
  [bea87d4a] SuiteSparse_jll v7.2.1+1
  [8e850b90] libblastrampoline_jll v5.11.0+0
Info Packages marked with ⌃ have new versions available and may be upgradable.
```

  - Output of `versioninfo()`

```julia
julia> versioninfo()
Julia Version 1.10.6
Commit 67dffc4a8ae (2024-10-28 12:23 UTC)
Build Info:
  Official https://julialang.org/ release
Platform Info:
  OS: macOS (arm64-apple-darwin24.0.0)
  CPU: 12 × Apple M2 Max
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, apple-m1)
Threads: 8 default, 0 interactive, 4 GC (on 8 virtual cores)
Environment:
  JULIA_EDITOR = code
  JULIA_NUM_THREADS = 8
```

**Additional context**

Related to https://github.com/trixi-framework/Trixi.jl/pull/2150#
