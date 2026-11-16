≔ (\coloneq) generates "invalid identifier" error
≔ (i.e. \coloneq) parsing fails with JuliaSyntax.
```
julia> ≔ = 1
ERROR: ParseError:
# Error @ REPL[2]:1:1
≔ = 1
╙ ── invalid identifier
Stacktrace:
 [1] top-level scope
   @ none:1
```
≔ is accepted as identifier character in FLISP parser.
```
julia> ≔ = 1
1
```

This with Julia 1.10
```
julia> versioninfo()
Julia Version 1.10.0
Commit 3120989f39b (2023-12-25 18:01 UTC)
```
