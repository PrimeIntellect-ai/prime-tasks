Expr constructor sometimes returns a Symbol, Bool, etc
Examples: https://github.com/julia-vscode/CSTParser.jl/blob/778212a77d2977b94a531240877eacff00700111/src/conversion.jl#L137-L142

I worry it's troubling to claim to be a constructor of a type and not return that type. That method could be called `expr_or_symbol`, or it could always return an `Expr` the way that Base does.

EDIT: but `_literal_expr` is going to be real trouble. Maybe this should be `expr_or_literal`?

### Additional contract requirements

- Calling `Expr` on a CST node must never produce a value that is not an `Expr`: it either returns an `Expr` or is not supported for that node.
- Converting a CST node to Julia's own representation of the same source remains available as `CSTParser.to_codeobject(node)`. For any parsed expression it returns the object that `Meta.parse` produces for that source, which can be an `Expr`, a `Symbol`, or a literal value such as an integer or float.
