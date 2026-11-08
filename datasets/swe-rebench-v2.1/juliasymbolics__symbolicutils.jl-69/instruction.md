substitution
This is like a "first pr" level issue in the broader problem space of context-based simplification.

`RuleSet([a => 1])(expr)` can replace `a` in `expr` with 1. But a much more efficient `substitute` function [HIDDEN] -- that way it can substitute many exprs at once.

### Additional contract requirements

- Provide a public, exported function `substitute(expr, dict)` in `SymbolicUtils`. `expr` is a symbolic expression and `dict` is a `Dict` whose keys are symbolic objects and whose values are the replacement expressions or values.
- `substitute` replaces every subexpression of `expr` that matches a key in `dict` with the corresponding value. This includes compound subexpressions: if a compound subexpression (for example a sum such as `a + b`) is a key in `dict`, that whole subexpression is replaced by its value.
- The returned expression retains the original structure apart from the performed substitutions; no additional simplification is applied unless the caller subsequently invokes `simplify`.
