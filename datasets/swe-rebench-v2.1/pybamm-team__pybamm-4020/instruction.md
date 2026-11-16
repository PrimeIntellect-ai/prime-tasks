"Throughput capacity [A.h]" is different for sol.cycles[0] and sol.cycles[0].steps[0]
### Discussed in https://github.com/pybamm-team/PyBaMM/discussions/2523

<div type='discussions-op-text'>

<sup>Originally posted by **RuiheLi** December  5, 2022</sup>
Dear PyBaMM,

I am using PyBaMM 22.9 and Python 3.9.6.

I find when using that set_initial_conditions_from, "Throughput capacity [A.h]" is different for sol.cycles[0] and sol.cycles[0].steps[0] for a later solution. Figure below:
![image](https://user-images.githubusercontent.com/84007676/205644495-558eabbe-1f36-4dd5-9935-44f131704896.png)


Script below:

```
import pybamm
import matplotlib as mpl
fs=17;
font = {'family' : 'DejaVu Sans','size'   : fs}
mpl.rc('font', **font)
V_max = 4.0;  V_min = 2.7;
model_0 = pybamm.lithium_ion.DFN(options={
    "calculate discharge energy":"true", },)
exp_AGE_text = [(f"Discharge at 1 C until {V_min} V",
    f"Charge at 1 C until {V_max} V", ),  ]
Experiment    = pybamm.Experiment( exp_AGE_text * 1)
Para_0 = pybamm.ParameterValues("OKane2022" )

Sim_0= pybamm.Simulation(
    model_0,
    experiment = Experiment,
    parameter_values=Para_0,
    solver = pybamm.CasadiSolver(),)
Sol_0 = Sim_0.solve(calc_esoh=False,)

model_1 = model_0.set_initial_conditions_from(Sol_0, inplace=False)
Sim_1= pybamm.Simulation(
    model_1,
    experiment = Experiment,
    parameter_values=Para_0,
    solver = pybamm.CasadiSolver(),)
Sol_1 = Sim_1.solve(calc_esoh=False,)

model_2 = model_0.set_initial_conditions_from(Sol_1, inplace=False)
Sim_2= pybamm.Simulation(
    model_2,
    experiment = Experiment,
    parameter_values=Para_0,
    solver = pybamm.CasadiSolver(),)
Sol_2 = Sim_2.solve(calc_esoh=False,)

label = ["Sol_0","Sol_1","Sol_2",]
output_variables3 = [
    "Throughput energy [W.h]",
    "Throughput capacity [A.h]",
    "Terminal voltage [V]",
]
quick_plot = pybamm.QuickPlot(
    [Sol_0,Sol_1,Sol_2,], output_variables3,label,variable_limits='fixed',
    time_unit='hours',n_rows=1) #figsize = (18,12),
quick_plot.dynamic_plot()
label = ["Sol_2 whole","Sol_2 cycles","Sol_2 steps",]
quick_plot = pybamm.QuickPlot(
    [Sol_2,Sol_2.cycles[0],Sol_2.cycles[0].steps[0]], output_variables3,label,variable_limits='fixed',
    time_unit='hours',n_rows=1) #figsize = (18,12),
quick_plot.dynamic_plot()
```

Do you have any ideas on this? Big thanks!

</div>

### Additional contract requirements

- `pybamm.Discretisation.__init__(self, mesh=None, spatial_methods=None, check_model=True, remove_independent_variables_from_rhs=False)` accepts a `check_model` option (default `True`) and a `remove_independent_variables_from_rhs` option (default `False`).
- `pybamm.Discretisation.process_model(self, model, inplace=True)` no longer accepts the per-call `check_model` or `remove_independent_variables_from_rhs` arguments.
- `pybamm.Simulation.__init__` accepts a `discretisation_kwargs` dictionary (default `None`) of options that are applied to the discretisation used to build the model, both for ordinary builds and for experiment builds.
- `pybamm.Simulation.build(self, initial_soc=None, inputs=None)` no longer accepts a `check_model` argument.
- `pybamm.Simulation.build_for_experiment(self, initial_soc=None, inputs=None)` no longer accepts a `check_model` argument.
- `pybamm.Simulation.solve(self, t_eval=None, solver=None, save_at_cycles=None, calc_esoh=True, starting_solution=None, inputs=None)` no longer accepts a `check_model` argument.
