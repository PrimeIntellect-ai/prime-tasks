R REPL Mode doesn't handle comments
`@R_str` seems fine, but the REPL mode gives an error:

```
R> x = 1 # comment
Error: unexpected end of input

julia> R"x = 1 # comment"
RObject{RealSxp}
[1] 1
```
