Parsing of generators allows skipping a comma
JuliaSyntax allows skipping a separator after a generator. In Julia 1.10 you have:

```julia
:(x for x in xs a, b) == :((x for x in xs), a, b)
```

Even more strangely, depending on the separator that comes after the expression may be parsed as a block or as a tuple:

```julia
julia> parsestmt(SyntaxNode, "(x for x = xs a; b)")
line:col│ tree                                   │ file_name
   1:1  │[block-p]
   1:2  │  [generator]
   1:2  │    x
   1:7  │    [=]
   1:8  │      x
   1:12 │      xs
   1:15 │  a
   1:18 │  b


julia> parsestmt(SyntaxNode, "(x for x = xs a, b)")
line:col│ tree                                   │ file_name
   1:1  │[tuple-p]
   1:2  │  [generator]
   1:2  │    x
   1:7  │    [=]
   1:8  │      x
   1:12 │      xs
   1:15 │  a
   1:18 │  b
```

~~This error isn't present in the flisp parser.~~ The error is present in the flisp parser, but only in certain contexts. In Julia 1.9, we have:
```julia
julia> :(x for x = xs a) # plain generator
ERROR: syntax: expected ")"
Stacktrace:
 [1] top-level scope
   @ none:1

julia> :(f(x for x = xs a)) # Generator inside call
:(f((x for x = in), a))
```
