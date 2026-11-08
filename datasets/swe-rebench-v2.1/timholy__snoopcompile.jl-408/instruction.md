`methods_with_generators` undefined when running `SnoopCompile.write`
Not quite a MRE, but the essence of the code was as follows:
```julia
tinf = @snoop_inference some_function()
(_, pcs) = SnoopCompile.parcel(tinf)
SnoopCompile.write("dir", pcs)
```

Sorry I forgot to grab the full stacktrace, but here's where `methods_with_generators` is called: https://github.com/timholy/SnoopCompile.jl/blob/d803b4e7a6ac65d344b4089d8aba3d08f2b7c96d/src/utils.jl#L96

Interestingly, the error occurred not immediately but after several statements like the following printed:
```
Base: precompiled 0.0013572730000000002 out of 0.003003319000000001
```

Hopefully it's just a missing import that's easy to fix, but if a better stacktrace is needed I can grab one.

EDIT: [Upon further inspection](https://github.com/search?q=lang%3AJulia+%22methods_with_generators%22&type=code), it appears this method was defined in earlier versions of SnoopCompile, but was removed for some reason.

### Additional contract requirements

- For inference results from `callgen407(3)`, `SnoopCompile.get_reprs` must return at least one string containing the exact substring `which(gen407,(Any,)).generator`.
