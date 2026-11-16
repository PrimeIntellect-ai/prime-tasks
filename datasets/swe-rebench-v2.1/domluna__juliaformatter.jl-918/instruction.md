Incorrect handling of `..` in `using` statements
Formatting the following text
```julia
using Measurements: (..)
```

Outputs the error
```
┌ Warning: Failed to format file /Users/jonnie.diegelman/github/FlightSystems/blah.jl due to a parsing error, skipping file
│   error =
│    ParseError:
│    # Warning @ line 1:21
│    using Measurements: (..)
│    #                   └──┘ ── parentheses are not required here
└ @ JuliaFormatter ~/.julia/packages/JuliaFormatter/D3w1R/src/JuliaFormatter.jl:448
```

This is incorrect. The parentheses are required, otherwise the code is not able to be parsed.

JuliaFormatter version: `v2.1.2`
Output of `versioninfo()`:
```
Julia Version 1.11.4
Commit 8561cc3d68d (2025-03-10 11:36 UTC)
Build Info:
  Official https://julialang.org/ release
Platform Info:
  OS: macOS (arm64-apple-darwin24.0.0)
  CPU: 8 × Apple M1
  WORD_SIZE: 64
  LLVM: libLLVM-16.0.6 (ORCJIT, apple-m1)
Threads: 4 default, 0 interactive, 2 GC (on 4 virtual cores)
```
