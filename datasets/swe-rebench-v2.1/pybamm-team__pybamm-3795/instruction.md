Check if the solution exists before creating a GIF (`Simulation.create_gif` and `BatchStudy.create_gif`)
I liked how #3723 checks if the simulations have been solved before proceeding ahead to the plotting functionality. It would be nice to have similar checks in -

https://github.com/pybamm-team/PyBaMM/blob/c3def31a04df163769851733657d9b49b3700bca/pybamm/batch_study.py#L184-L187

and

https://github.com/pybamm-team/PyBaMM/blob/c3def31a04df163769851733657d9b49b3700bca/pybamm/simulation.py#L1047-L1050
