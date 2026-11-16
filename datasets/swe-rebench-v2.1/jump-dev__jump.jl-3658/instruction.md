Add support for MOI.ScalarQuadraticCoefficientChange
MOI v1.21 added `MOI.ScalarQuadraticCoefficientChange`: https://github.com/jump-dev/MathOptInterface.jl/pull/2296

We should expose this at the JuMP level, but maybe wait for https://github.com/jump-dev/HiGHS.jl/pull/195 to be merged.

### Additional contract requirements

JuMP must allow users to set or replace a quadratic coefficient in a scalar quadratic constraint and observe the updated value. It must also allow users to set or replace a quadratic coefficient in the objective, whether the existing objective is quadratic, affine, variable-only, or absent. This includes both square terms and products of distinct variables; setting a product with the variables in reversed order updates the same coefficient.
