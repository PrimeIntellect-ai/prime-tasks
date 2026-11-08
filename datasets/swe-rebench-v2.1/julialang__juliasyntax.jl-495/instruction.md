wrong line numbers with lines ending in ;
<!--
1. The output of `versioninfo()`
2. How you installed Julia
3. A minimal working example (MWE), also known as a minimum reproducible example

If you're experiencing a problem with a particular package, open an issue on that
package's repository instead.

Thanks for contributing to the Julia project!
-->


take this file
test.jl
```julia
function f(x,y)
end

f(;1;2);
```
and
test2.jl
```julia
function f(x,y)
end

f(;1;2)
```


in julia 1.6 i get the error pointed on the same line
```
ERROR: LoadError: syntax: more than one semicolon in argument list around /home/antineutrino/test.jl:4
Stacktrace:
 [1] top-level scope
   @ ~/test.jl:4
in expression starting at /home/antineutrino/test.jl:4
ERROR: LoadError: syntax: more than one semicolon in argument list around /home/antineutrino/test2.jl:4
Stacktrace:
 [1] top-level scope
   @ ~/test2.jl:4
in expression starting at /home/antineutrino/test2.jl:4
```

however in julia 1.10 i get errors pointed out on different lines

```
└N julia +release test.jl; julia +release test2.jl
ERROR: LoadError: syntax: more than one semicolon in argument list around /home/antineutrino/test.jl:2
Stacktrace:
 [1] top-level scope
   @ ~/test.jl:2
in expression starting at /home/antineutrino/test.jl:2
ERROR: LoadError: syntax: more than one semicolon in argument list around /home/antineutrino/test2.jl:4
Stacktrace:
 [1] top-level scope
   @ ~/test2.jl:4
in expression starting at /home/antineutrino/test2.jl:4
```

versioninfo for +release
```
julia> versioninfo()
Julia Version 1.10.4
Commit 48d4fd48430 (2024-06-04 10:41 UTC)
Build Info:
  Official https://julialang.org/ release
Platform Info:
  OS: Linux (x86_64-linux-gnu)
  CPU: 8 × Intel(R) Xeon(R) CPU E3-1270 v5 @ 3.60GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, skylake)
Threads: 1 default, 0 interactive, 1 GC (on 8 virtual cores)
```
