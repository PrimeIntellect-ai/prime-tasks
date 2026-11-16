v2.12.2 breaks compatibility of produce_or_load() and datadir()
**Describe the bug**
When using `produce_or_load(datadir("sims"), myparams, myfun)`  in v2.12.2 (.1 works fine) I get the error
```
MethodError: no method matching produce_or_load(::SubString{String}, ::Dict{String, Any}, ::typeof(myfun))
```

It seems that a String instead of the SubString would work.
Maybe related to #380 ?

**Minimal Working Example**
Sorry, I have no MWE yet.

```
julia> versioninfo()
Julia Version 1.8.5
Commit 17cfb8e65e (2023-01-08 06:45 UTC)
Platform Info:
  OS: Windows (x86_64-w64-mingw32)
  CPU: 8 × 11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-13.0.1 (ORCJIT, tigerlake)
  Threads: 8 on 8 virtual cores
Environment:
  JULIA_EDITOR = code
```
