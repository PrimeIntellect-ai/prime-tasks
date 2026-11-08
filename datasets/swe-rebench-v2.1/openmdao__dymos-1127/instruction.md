Simulation step fails with shape error when parameter is an N-dimensional array
### Description

Sometimes a parameter input to a Dymos ODE needs to be something other than a scalar or 1-D array. One such situation might be when the ODE describes 6 degree of freedom motion, where the Moment of Inertia matrix of the body whose motion you want to simulate is a parameter for the phase and trajectory.

It turns out that the parameters with shapes greater than 1-D work when finding the solution -- that is calling
dymos.run_problem(p, run_driver=True, simulate=False)

However, when setting the "simulate" flag to True, the simulation fails with this error

```
   File dymos\utils\introspection.py:471 in configure_parameters_introspection
    raise RuntimeError(f'Shape provided to parameter `{name}` differs from its targets.\n'
```

A minimal example is provided that reproduces the behavior

### Example

    import numpy as np
    import openmdao.api as om
    import dymos as dm


    class ODE(om.Group):

        def initialize(self):
            self.options.declare("num_nodes", types=int)

        def setup(self):

            nn = self.options["num_nodes"]
            lin_sys = om.LinearSystemComp(
                size=3,
                vec_size=nn,
                vectorize_A=True,
            )

            self.add_subsystem(
                "rates",
                lin_sys,
                promotes_inputs=["*"],
                promotes_outputs=["*"],
            )


    p = om.Problem()
    p.driver = om.pyOptSparseDriver()
    p.driver.options["optimizer"] = "SNOPT"
    p.driver.opt_settings["Major iterations limit"] = 100
    p.driver.options["print_results"] = False


    t = dm.Radau(num_segments=20, order=3)
    phase = dm.Phase(ode_class=ODE, transcription=t)


    phase.set_time_options(fix_initial=True, duration_bounds=(5, 60), duration_ref=1)
    phase.add_state("w", fix_initial=True, rate_source="x")
    phase.add_control("M", opt=False, targets=["b"], lower=-50, upper=50)
    phase.set_control_options("M", val=np.array([30, -50, 50]))

    A_mat = np.array(
        [
            [10, 0, 0],
            [0, 10, 0],
            [0, 0, 10],
        ]
    )

    # argument "dynamic" doesn't seem to help
    phase.add_parameter("A", val=A_mat, targets=["A"])
    phase.add_objective("time", loc="final", scaler=1)

    traj = dm.Trajectory()
    traj.add_phase("phase0", phase)

    p.model.add_subsystem("traj", traj)

    p.driver.declare_coloring()
    p.setup(force_alloc_complex=True)

    # This works
    # dm.run_problem(p, run_driver=True, simulate=False, make_plots=True)
    # This doesn't
    dm.run_problem(p, run_driver=True, simulate=True, make_plots=True)


### Dymos Version

1.10.0

### Relevant environment information

OpenMDAO version 3.32.0
Dymos version 1.10.0

### Additional contract requirements

- The module `dymos.examples.oscillator.oscillator_ode` must provide an importable `OscillatorVectorODE`.
- `OscillatorVectorODE` must accept a Boolean option `static_params`, including when supplied through `Phase(..., ode_init_kwargs={'static_params': static_params})`.
- `Phase.add_parameter` must accept a `static_target` argument that defaults to `False`. When `static_target` is `False` the parameter is dynamic (its value may vary at each node); when it is `True` the parameter is static (the same value at all nodes).
- For `OscillatorVectorODE` with initial state `[1, 0]` and parameter matrix `A = [[0, 1], [-1, 0]]`, the simulated final state `x` must equal `[cos(t_f), -sin(t_f)]` within tolerance `1e-5`, where `t_f` is the final timeseries time.
