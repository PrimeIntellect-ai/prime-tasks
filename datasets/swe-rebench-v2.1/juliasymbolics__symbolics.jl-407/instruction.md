Proper `solve_for` for linear system of equations
Currently, we solve a linear system by solve the Jacobian matrix. Unfortunately, taking the derivative and then doing the linear algebra introduces round-off errors. We need a proper `solve_for` that doesn't leave unknowns in the result.
