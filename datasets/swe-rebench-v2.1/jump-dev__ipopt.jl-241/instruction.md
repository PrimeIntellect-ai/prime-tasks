Implement MOI solver-dependent callback
I am using `Ipopt` for solving a NLP. I would like to have access to the intermediate state of the optimisation problem, at each iteration. I know Ipopt has a callback function for this purpose. Is this feature not exposed in JuMP? Are any of the solvers callback functions exposed, for that matter? Thank you!

### Additional contract requirements

For an MOI optimizer, users can register the intermediate callback with `MOI.set(model, Ipopt.CallbackFunction(), callback)`. During optimization it is called with Ipopt's intermediate iteration data in this positional order: the low-level problem, algorithm mode, iteration number, objective value, primal infeasibility, dual infeasibility, barrier parameter, step norm, regularization size, dual step size, primal step size, and line-search trial count. In particular, the iteration number and objective value let the user inspect optimization progress. The callback's return value need not interrupt the solve.
