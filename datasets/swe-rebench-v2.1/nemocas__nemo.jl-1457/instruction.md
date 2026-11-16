no method matching `zero(::Type{qqbar})`
Hi! I need method `zero(::Type{qqbar})` for using QQBar with SparseArrays.jl. I am wondering if it's possible to add it ? thank you.

The following is curious:

```julia
using Nemo
qqbar(0)       # works !
zero(qqbar)    # doesn't work :(
```
