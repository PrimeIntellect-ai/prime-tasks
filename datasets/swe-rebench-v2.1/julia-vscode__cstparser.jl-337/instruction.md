`const` field support
Is there a plan for supporting `const` field, which is added in Julia 1.8 (not released as of writing)?

```julia
julia> code = """mutable struct S; const f; end""";

julia> CSTParser.parse(code)
  1:30  struct
  1:0    TRUE: nothing
  1:3    S
  4:12   block
  4:12    const
  4:6      errortoken( CSTParser.ExpectedAssignment)
  4:6       f

julia> Meta.parse(code)
:(mutable struct S
      #= none:1 =#
      const f
  end)

(jl_ba4y9i) pkg> st
Status `/tmp/jl_ba4y9i/Project.toml`
  [00ebfdb7] CSTParser v3.3.3
```
