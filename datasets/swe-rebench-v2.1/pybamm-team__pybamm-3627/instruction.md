Pass array of times to `step`
When you call `solver.step` you pass in `dt`, the time time increment you want to step forward in. You can also pass `npts` to get the solution back at a linearly spaced array of times between the initial time, `t0`, and `t0+dt`. It would be good to instead be able to pass an array of times, `t_eval`, like you pass to solve, so you can get step solutions returned at non-linearly spaced times.

The motivation for this is that right now you can't pass a `starting_solution` to `Simualtion.solve` if you aren't using an experiment, so if you want to chain solutions together you have to call `Simulation.step` instead.

An alternative is that we allow starting solutions without experiments in `Simulation.solve`.

The whole logic for `step` and `solve` is pretty clunky both in `Simulation` and `BaseSolver`, but that's a separate issue...

### Additional contract requirements

- `BaseSolver.step(old_solution, model, dt, t_eval=None, npts=None, inputs=None, save=True)` accepts an optional `t_eval` argument: a list or numpy array of times measured from the start of the step. When `t_eval` is omitted, the solution is returned at the start and end of the step (`t0` and `t0 + dt`). When `t_eval` is supplied, the returned `pybamm.Solution` contains the solution at those times.
- `t_eval` must start at 0 and end at `dt`; otherwise `BaseSolver.step` raises `pybamm.SolverError` with the message "Elements inside array t_eval must lie in the closed interval 0 to dt".
- Supplying `npts` is deprecated: it emits a `DeprecationWarning` and is converted to an equally spaced `t_eval` with `npts` points between 0 and `dt`.
- `Simulation.step(dt, solver=None, t_eval=None, save=True, starting_solution=None, **kwargs)` accepts an optional `t_eval` argument and returns the stepped `pybamm.Solution` at those times.
