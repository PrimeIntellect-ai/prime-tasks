Add support for GetIpoptCurrentViolations
Asked for on SO: https://stackoverflow.com/questions/75547527/access-the-complementarity-infeasibility-dual-infeasibility-and-the-primal-inf

x-ref https://coin-or.github.io/Ipopt/IpStdCInterface_8h.html#ae505cff0e907b9049062f665dadd8be9

This is a new feature added in v3.14.0

### Additional contract requirements

`GetIpoptCurrentViolations` overwrites every supplied buffer with the current
metric. In particular, for the current iterate `x`, `z_L`, `z_U` returned by
`GetIpoptCurrentIterate`:

- `compl_x_L[i] = z_L[i] * (x[i] - x_L[i])` and
  `compl_x_U[i] = z_U[i] * (x_U[i] - x[i])`, to within `1e-6`.
- `grad_lag_x` and `compl_g` are filled with finite values.

The `scaled` argument of both functions selects between the scaled and the
unscaled values. With user scaling factors `x_scaling` (length `n`) and
`g_scaling` (length `m`), the scaled values satisfy
`x_scaled = x_unscaled .* x_scaling`,
`g_scaled = g_unscaled .* g_scaling`, and
`nlp_constraint_violation_scaled = nlp_constraint_violation_unscaled .* g_scaling`.
