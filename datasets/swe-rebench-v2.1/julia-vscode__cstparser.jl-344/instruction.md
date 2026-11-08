Incorrect parsing with `global const ...`
```
julia> s
"global const SOME_GLOBAL_VAR_NAME = \"SOME_GLOBAL_VAR_NAME\"\n"

julia> x = CSTParser.parse(s)
  1:59  const
  1:46   global
  1:46      1:2   OP: =
  1:21     SOME_GLOBAL_VAR_NAME
 22:44     STRING: SOME_GLOBAL_VAR_NAME

julia> x[1]
  1:7   GLOBAL

julia> x[2]
  1:6   CONST

julia> x[3]
  1:46  global
  1:46     1:2   OP: =
  1:21    SOME_GLOBAL_VAR_NAME
 22:44    STRING: SOME_GLOBAL_VAR_NAME
```

It seems that x[2] should be a new node tree where the first arg in CONST and then the assignment op follows.

https://github.com/domluna/JuliaFormatter.jl/issues/581
