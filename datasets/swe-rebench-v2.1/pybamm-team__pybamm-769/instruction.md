non-identity mass in casadi
casadi expects to receive the dae in semi-explicit form:
```
x_dot = f(t,x,z)
0 = g(t,x,z)
```
but pybamm gives daes in the form
```
M*x_dot = f(t,x,z)
0 = g(t,x,z)
```
where M is the mass matrix. For finite volumes M is the identity, so this is not a problem. [HIDDEN] The mass matrix is always block diagonal, and most of the blocks are identity (for now, since we only have finite volumes in the x direction), so inverting the matrix only requires inversion of some (typically at most one) of the blocks, which is very cheap.

### Additional contract requirements

- After discretisation, the discretised model exposes the inverse of the differential (ODE) part of its mass matrix as `mass_matrix_inv`, a `pybamm.Matrix`, alongside the existing `mass_matrix`. `mass_matrix_inv` can also be assigned a `pybamm.Matrix` directly.
- When solving a model with a non-identity mass matrix, the differential equations are provided to CasADi in explicit form, and the algebraic equations are preserved.
