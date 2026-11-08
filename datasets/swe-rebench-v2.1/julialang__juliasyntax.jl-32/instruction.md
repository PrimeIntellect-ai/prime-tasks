Some tokenize issues
Running the tests from the system image, I found some broken tests due to operators which should be errors, but the JuliaSyntax lexer tokenizes them as operators:

```
julia> broken_ops = [
        "a .-> b",
        "a .>: b",
        "a .<: b",
        "a ||₁ b",
        "a ||̄ b",
        "a .||₁ b",
        "a &&₁ b",
        "a &&̄ b",
        "a .&&₁ b",
       ]
9-element Vector{String}:
 "a .-> b"
 "a .>: b"
 "a .<: b"
 "a ||₁ b"
 "a ||̄ b"
 "a .||₁ b"
 "a &&₁ b"
 "a &&̄ b"
 "a .&&₁ b"

julia> [[JuliaSyntax.Tokenize.untokenize(t, s) for t in JuliaSyntax.Tokenize.tokenize(s)] for s in broken_ops]
9-element Vector{Vector{String}}:
 ["a", " ", ".->", " ", "b", ""]
 ["a", " ", ".>:", " ", "b", ""]
 ["a", " ", ".<:", " ", "b", ""]
 ["a", " ", "||₁", " ", "b", ""]
 ["a", " ", "||̄", " ", "b", ""]
 ["a", " ", ".||₁", " ", "b", ""]
 ["a", " ", "&&₁", " ", "b", ""]
 ["a", " ", "&&̄", " ", "b", ""]
 ["a", " ", ".&&₁", " ", "b", ""]
```

### Additional contract requirements

- For each listed input, the ordered strings obtained by untokenizing its tokens against that input must be exactly:
- `a .-> b`: `["a", " ", ".-", ">", " ", "b", ""]`
- `.>: b`: `[".>:", " ", "b", ""]`
- `.<: b`: `[".<:", " ", "b", ""]`
- `a ||₁ b`: `["a", " ", "||", "₁", " ", "b", ""]`
- `a ||̄ b`: `["a", " ", "||", "̄", " ", "b", ""]`
- `a .||₁ b`: `["a", " ", ".||", "₁", " ", "b", ""]`
- `a &&₁ b`: `["a", " ", "&&", "₁", " ", "b", ""]`
- `a &&̄ b`: `["a", " ", "&&", "̄", " ", "b", ""]`
- `a .&&₁ b`: `["a", " ", ".&&", "₁", " ", "b", ""]`
- In the listed `||`, `&&`, `.||`, and `.&&` inputs, each following subscript or combining mark must be reported as an error token, rather than accepted as part of a valid operator.
- For `a .-> b`, `.>: b`, and `.<: b`, the listed token sequence is the whole requirement; these inputs are not required to produce error tokens.
