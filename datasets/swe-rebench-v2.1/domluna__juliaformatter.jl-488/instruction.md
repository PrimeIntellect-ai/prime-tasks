3 space alignment after ifs should not be done for BlueStyle
Consider the following code.
It is valid-ish according to BlueStyle.
Valid-ish becuase BlueStyle doesn't make any statement about breaking lines after boolean operators to stay within line limits
So it should be left alone.
```julia
    if primal_name isa Symbol ||
        Meta.isexpr(primal_name, :(.)) ||
        Meta.isexpr(primal_name, :curly)

        foo()
    end
```

The output of  JuliaFormatter on the other hand is not right.

```julia
julia> format_text(str, BlueStyle()) |> println
if primal_name isa Symbol ||
   Meta.isexpr(primal_name, :(.)) ||
   Meta.isexpr(primal_name, :curly)
    foo()
end
```

It has changed to use 3 spaces to align with the `if`.
BlueStyle *never* does visual alignment, only indenting with 4 spaces.

### Additional contract requirements

- For the input `if a && b`, with BlueStyle and a maximum line width of 1, the formatted output must be exactly:
```julia
if a &&
    b
end
```
- Also, with BlueStyle, four-space indentation, and a maximum line width of 1, each of these inputs must be returned exactly unchanged:
```julia
const a =
    arg1 +
    arg2 +
    arg3
```
```julia
const a =
    arg1 +
    arg2
```
