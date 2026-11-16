default propertynames/getproperty and columnnames/getcolumn definitions for AbstractRow are mutually recursive
This might just be a documentation issue (or I could've missed something), but:

```jl
julia> struct Foo <: Tables.AbstractRow
           x::Int
       end

julia> propertynames(Foo(1))
ERROR: StackOverflowError:
Stacktrace:
 [1] propertynames(::Foo) at /Users/jarrettrevels/.julia/dev/Tables/src/Tables.jl:167
 [2] columnnames(::Foo) at /Users/jarrettrevels/.julia/dev/Tables/src/Tables.jl:105
 ... (the last 2 lines are repeated 39990 more times)
 [79983] propertynames(::Foo) at /Users/jarrettrevels/.julia/dev/Tables/src/Tables.jl:167

julia> Tables.columnnames(Foo(1))
ERROR: StackOverflowError:
Stacktrace:
 [1] columnnames(::Foo) at /Users/jarrettrevels/.julia/dev/Tables/src/Tables.jl:105
 [2] propertynames(::Foo) at /Users/jarrettrevels/.julia/dev/Tables/src/Tables.jl:167
 ... (the last 2 lines are repeated 39990 more times)
 [79983] columnnames(::Foo) at /Users/jarrettrevels/.julia/dev/Tables/src/Tables.jl:105
```

ref https://github.com/JuliaData/Tables.jl/blob/fdf4d114bbca31e547c18cde9c18ff84ac093e09/src/Tables.jl#L105

ref https://github.com/JuliaData/Tables.jl/blob/fdf4d114bbca31e547c18cde9c18ff84ac093e09/src/Tables.jl#L167

[HIDDEN] I'm a Tables newcomer, so I'm unsure which approach is preferred (I'm assuming the latter?). I'm guessing a similar issue exists for AbstractColumns but haven't checked.

EDIT:

> documenting that one of these two functions *must* be overloaded by new `AbstractRow` subtypes

`getcolumn` etc is under "Required Methods" in the docs, but I interpret that in combo with "Default Definition"  to mean "this method needs to be defined *somewhere*; if the default definition seems good, then you're good to go"

### Additional contract requirements

- For a concrete type `T <: Union{Tables.AbstractRow, Tables.AbstractColumns}` that does not define its own `Tables.getcolumn(::T, ::Int)` method, calling `Tables.getcolumn(x, i)` with an `Int` index `i` raises an `ErrorException` whose message is:

      `Tables.getcolumn` must be specifically overloaded for <T> <: Union{AbstractRow, AbstractColumns}`

  where `<T>` is the concrete subtype name.
- For a concrete type `T <: Union{Tables.AbstractRow, Tables.AbstractColumns}` that does not define its own `Tables.getcolumn(::T, ::Symbol)` method, calling `Tables.getcolumn(x, name)` with a `Symbol` name raises an `ErrorException` whose message is:

      `Tables.getcolumn` must be specifically overloaded for <T> <: Union{AbstractRow, AbstractColumns}`

  where `<T>` is the concrete subtype name.
- For a concrete type `T <: Union{Tables.AbstractRow, Tables.AbstractColumns}` that does not define its own `Tables.columnnames` method, calling `Tables.columnnames(x)` raises an `ErrorException` whose message is:

      `Tables.columnnames` must be specifically overloaded for <T> <: Union{AbstractRow, AbstractColumns}`

  where `<T>` is the concrete subtype name.
- The default property-name and property-access paths (`propertynames` and `getproperty`) for a bare `Tables.AbstractRow` or `Tables.AbstractColumns` subtype must terminate instead of recursing between `propertynames`/`getproperty` and `columnnames`/`getcolumn`.
