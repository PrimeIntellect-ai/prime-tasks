Test failure in RelSeries powering to exponent 0
```
Generic.RelSeries.powering: Test Failed at /Users/runner/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/generic/RelSeries-test.jl:613
  Expression: isequal(r1, r2)
   Evaluated: isequal(O(x^0), 1 + O(x^10))
Stacktrace:
 [1] macro expansion
   @ /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Test/src/Test.jl:445 [inlined]
 [2] macro expansion
   @ ~/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/generic/RelSeries-test.jl:613 [inlined]
 [3] macro expansion
   @ /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Test/src/Test.jl:1282 [inlined]
 [4] top-level scope
   @ ~/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/generic/RelSeries-test.jl:561
Test Summary:              | Pass  Fail  Total
Generic.RelSeries.powering | 2705     1   2706
ERROR: LoadError: Some tests did not pass: 2705 passed, 1 failed, 0 errored, 0 broken.
in expression starting at /Users/runner/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/generic/RelSeries-test.jl:559
in expression starting at /Users/runner/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/Rings-test.jl:8
in expression starting at /Users/runner/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/AbstractAlgebra-test.jl:4
in expression starting at /Users/runner/work/AbstractAlgebra.jl/AbstractAlgebra.jl/test/runtests.jl:113
ERROR: Package AbstractAlgebra errored during testing
Stacktrace:
 [1] pkgerror(msg::String)
   @ Pkg.Types /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Pkg/src/Types.jl:68
 [2] test(ctx::Pkg.Types.Context, pkgs::Vector{Pkg.Types.PackageSpec}; coverage::Bool, julia_args::Cmd, test_args::Cmd, test_fn::Nothing, force_latest_compatible_version::Bool, allow_earlier_backwards_compatible_versions::Bool, allow_reresolve::Bool)
   @ Pkg.Operations /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Pkg/src/Operations.jl:1681
 [3] test(ctx::Pkg.Types.Context, pkgs::Vector{Pkg.Types.PackageSpec}; coverage::Bool, test_fn::Nothing, julia_args::Cmd, test_args::Cmd, force_latest_compatible_version::Bool, allow_earlier_backwards_compatible_versions::Bool, allow_reresolve::Bool, kwargs::Base.Pairs{Symbol, IOContext{Base.PipeEndpoint}, Tuple{Symbol}, NamedTuple{(:io,), Tuple{IOContext{Base.PipeEndpoint}}}})
   @ Pkg.API /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Pkg/src/API.jl:426
 [4] test(pkgs::Vector{Pkg.Types.PackageSpec}; io::IOContext{Base.PipeEndpoint}, kwargs::Base.Pairs{Symbol, Bool, Tuple{Symbol, Symbol}, NamedTuple{(:coverage, :force_latest_compatible_version), Tuple{Bool, Bool}}})
   @ Pkg.API /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Pkg/src/API.jl:154
 [5] test(; name::Nothing, uuid::Nothing, version::Nothing, url::Nothing, rev::Nothing, path::Nothing, mode::Pkg.Types.PackageMode, subdir::Nothing, kwargs::Base.Pairs{Symbol, Bool, Tuple{Symbol, Symbol}, NamedTuple{(:coverage, :force_latest_compatible_version), Tuple{Bool, Bool}}})
   @ Pkg.API /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.8/Pkg/src/API.jl:169
 [6] top-level scope
   @ none:1
Error: Process completed with exit code 1.
```
