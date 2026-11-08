Support space-seperated short option forms
At the moment, if I have an option say
```
-e, --example <int>: this is an example
```
I can supply this option four ways:
```
julia demo.jl -- -e1
julia demo.jl -- -e=1
julia demo.jl -- --example 1
julia demo.jl -- --example=1
```
There's a fifth standard way that seems to have been overlooked:
```
julia demo.jl -- -e 1
```
It would be nice if Comonicon could support this.
