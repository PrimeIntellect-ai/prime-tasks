Rename `.m` field of some structs
Just spotted this TODO:
https://github.com/jump-dev/JuMP.jl/blob/5bdec266ea2dc435d1ff3237930410faf2cf0411/src/JuMP.jl#L1365

### Additional contract requirements

The `.m` field of the `NonlinearExpression`, `NonlinearParameter`, and
`NLPEvaluator` structs must be renamed to `.model`, so that the associated model
is accessible as `expr.model`, `p.model`, and `d.model` respectively.
