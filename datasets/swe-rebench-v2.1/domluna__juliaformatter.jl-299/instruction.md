`//` rational number constructor should use more spaces
The `//` rational number constructor doesn't use spaces when its arguments are complex expressions:
```Julia
julia> format_text("((-1)^s * factorial(i) * factorial(n)) // (2^n * factorial(i+n))")
"((-1)^s * factorial(i) * factorial(n))//(2^n * factorial(i + n))"
```
Both numerator and denominator are long expressions that contains spaces, yet the `//` operator binds tightly without spaces. This also leads to problems with line breaks – line breaks near the `//` won't happen.

It's fine if simple expressions such as `1//2` are rendered without spaces, but that looks strange for more complex expressions.
