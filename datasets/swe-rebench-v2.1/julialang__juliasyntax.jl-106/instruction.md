Bug parsing exception spec in `catch`
Spotted by @BenChung

```julia
julia> itest_parse(JuliaSyntax.parse_expr, "try 3 catch e+3 end")
# Code:
try 3 catch e+3 end

# Green tree:
     1:19     │[try]
     1:3      │  try                        "try"
     4:5      │  [block]
     4:4      │    Whitespace               " "
     5:5      │    Integer              ✔   "3"
     6:6      │  Whitespace                 " "
     7:11     │  catch                      "catch"
    12:12     │  Whitespace                 " "
    13:13     │  Identifier             ✔   "e"
    14:15     │  [block]
    14:15     │    Integer              ✔   "+3"
    16:16     │  Whitespace                 " "
    17:16     │  false                  ✔   ""
    17:16     │  false                  ✔   ""
    17:19     │  end                        "end"
```

Whereas the reference parser provides the error `invalid syntax "catch (e + 3)"`

### Additional contract requirements

- For `try x catch e+3 y end`, the parse tree must be `(try (block x) (error (call-i e + 3)) (block y) false false)`.
