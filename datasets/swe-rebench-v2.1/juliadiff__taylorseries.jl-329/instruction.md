Add Aqua tests
I recently precompiled a package that indirectly depends on TaylorSeries.jl, and saw these warnings:

```
julia> import ClimaCore
[ Info: Precompiling ClimaCore [d414da3d-4745-48bb-8d80-42e94e092884]
┌ Warning: AES-NI is not enabled, so AESNI and ARS are not available.
└ @ Random123 ~/.julia/packages/Random123/u5oEp/src/Random123.jl:55
WARNING: method definition for getindex at /Users/charliekawczynski/.julia/packages/TaylorSeries/YHybm/src/auxiliary.jl:125 declares type variable T but does not use it.
WARNING: method definition for getindex at /Users/charliekawczynski/.julia/packages/TaylorSeries/YHybm/src/auxiliary.jl:161 declares type variable T but does not use it.
```

This is perhaps an older version of TaylorSeries, but I think we should add Aqua.jl tests to prevent this from happening in the future.

### Additional contract requirements

- The package's test suite must include Aqua.jl tests, wired into the package's
  test runner so that they run whenever the package tests are run.
