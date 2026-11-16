Inconsistent solution keys across `variable_ne_branch_*` methods
### `variable_ne_branch_power_real`

`variable_ne_branch_power_real(pm::AbstractPowerModel; nw, bounded, report)` defines `:pf` and `:pt` as solution keys when assigning variables to solution dict:
https://github.com/lanl-ansi/PowerModels.jl/blob/c9544b5b1a4b78b91955a750320a7a917670fc36/src/core/variable.jl#L1204

However, `variable_ne_branch_power_real(pm::AbstractAPLossLessModels; nw, bounded, report)` uses `:p_ne_fr` and `:p_ne_to` instead:
https://github.com/lanl-ansi/PowerModels.jl/blob/c9544b5b1a4b78b91955a750320a7a917670fc36/src/form/dcp.jl#L283

---

### `variable_ne_branch_power_imaginary`

Similarly, `variable_ne_branch_power_imaginary(pm::AbstractPowerModel; nw, bounded, report)` uses `:qf` and `:qt`, whereas `variable_ne_branch_power_imaginary(pm::AbstractActivePowerModel; nw, bounded, report)` uses `:q_ne_fr` and `:q_ne_to`:
https://github.com/lanl-ansi/PowerModels.jl/blob/c9544b5b1a4b78b91955a750320a7a917670fc36/src/form/apo.jl#L32-L33

---

### Other functions

I also performed a similar search in other `variable_ne_*` functions: it seems that [`variable_ne_branch_cosine`](https://github.com/lanl-ansi/PowerModels.jl/blob/c9544b5b1a4b78b91955a750320a7a917670fc36/src/form/lpac.jl#L197-L227) and [`variable_ne_branch_voltage_product_angle`](https://github.com/lanl-ansi/PowerModels.jl/blob/c9544b5b1a4b78b91955a750320a7a917670fc36/src/form/lpac.jl#L229-L241) are the only ones that use `:*_ne*` in solution keys (`:cs_ne` and `:td_ne`, respectively). Perhaps those keys could be changed into `:cs` and `:td` for consistency.

### Additional contract requirements

The solution keys reported for `ne_branch` must be consistent with those reported for `branch`: for every model, the `ne_branch` solution dictionary must contain every key that the `branch` solution dictionary contains. In particular, `variable_ne_branch_cosine` must report its solution under the key `:cs` and `variable_ne_branch_voltage_product_angle` must report its solution under the key `:td`, matching the regular-branch keys.
