Empty docstring causes a bounds error
If a blank command description is given, a bounds error is thrown.

```julia
using Comonicon
"""
"""
@main
```

This is caused by
https://github.com/comonicon/Comonicon.jl/blob/ebb18333389d6cdbaae2c191315d4b8c8de5290c/src/frontend/markdown.jl#L134-L140

[HIDDEN]

###### Comonicon 0.12.17/master

### Additional contract requirements

- A command with an empty or blank docstring must be constructible and usable without raising a bounds error.
