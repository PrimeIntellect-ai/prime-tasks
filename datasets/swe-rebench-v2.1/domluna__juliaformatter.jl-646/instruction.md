error formatting `stdlib` of Julia
```julia

julia> format("./stdlib/", MinimalStyle(); normalize_line_endings = "unix", align_assignment=true)
[ Info: Error in formatting file stdlib/InteractiveUtils/test/runtests.jl
ERROR: ArgumentError: invalid index: nothing of type Nothing
```

### Additional contract requirements

- Formatting with `align_assignment = true` (indent 4, margin 92) must not raise an error for consecutive macro-decorated assignments such as:
  ```julia
  @foo @noinline Base.@constprop :none aaaaaaaaaaaaa() = 0
  @foo @noinline Base.@constprop :none bbbbbbbbbbbbbbbbbbb()     = 0
  @foo @foo @ccccccccccccccccccccccccccccccccccccccccccccccccc() = 0
  ```
- For that input, the `=` of each of the three assignment lines must start at the same column in the output, and the only change to the text may be in the runs of spaces.
- Formatting the following input with `align_assignment = true` (indent 4, margin 92) must return it unchanged:
  ```julia
  @foo @noinline Base.@constprop :none aaaaaaaaaaaaa() = 0
  @foo @noinline Base.@constprop :none bbbbbbbbbbbbbbbbbbbbbbb() = 0
  @foo @foo @ccccccccccccccccccccccccccccccccccccccccccccccccc() = 0
  ```
