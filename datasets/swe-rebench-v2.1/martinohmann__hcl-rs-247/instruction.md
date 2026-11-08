`$${` should be evaluated to `${`
`TemplateExpr::evaluate` right now will return literal `$${` for `$${` sequence in input.
