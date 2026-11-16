Support `asinh, acosh, atanh`.
The three inverse hyperbolic functions `asinh, acosh, atanh` are the only trig functions yet to be implemented.

Once these are defined on series, Julia’s full suite of standard trig functions

    sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, asinh, acosh, atanh, csc, sec, cot, acsc, asec, acot, csch, sech, coth, acsch, asech, acoth

will be supported, thanks to the default definitions like `acsch(x::Number) = inv(asinh(x))` in `Base`.

This should be an easy fix. (I would make a PR myself, but the actual code in `functions.jl` is a bit obscure…)

### Additional contract requirements

- Add public functions `asinh(a)`, `acosh(a)` and `atanh(a)` for `a` a `Taylor1` or `TaylorN` series. Each returns a series of the same type and order as `a`.
- `asinh(a)` raises `ArgumentError` when the constant term `a0` of `a` satisfies `a0^2 + 1 == 0`.
- `acosh(a)` raises `ArgumentError` when the constant term `a0` of `a` satisfies `a0^2 == 1`.
- `atanh(a)` raises `ArgumentError` when the constant term `a0` of `a` satisfies `a0^2 == 1`.
