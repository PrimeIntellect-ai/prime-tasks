Overlapping constraints in Birkhoff transcription
### Description

Adding a boundary constraint and a path constraint for variables of any type other than state causes the error.

The lines of code when added to the brachistochrone problem throw the error

`RuntimeError: <model> <class Group>: Indices for aliases ['traj.phases.phase0->final_boundary_constraint->theta', 'traj.phases.phase0->path_constraint->theta'] are overlapping constraint/objective 'traj.phases.phase0.timeseries.timeseries_comp.theta'.`


### Example

phase.add_path_constraint('theta', lower=0.01, upper=179.9)
phase.add_boundary_constraint('theta', loc='final', lower=0.01, upper=179.9)


### Dymos Version

1.9.2.dev0

### Relevant environment information

_No response_

### Additional contract requirements

- The overlapping-constraint fix applies to non-state variables that are controls (including control rates) and ODE outputs. Parameters remain constant over a phase and may not have both a path constraint and a boundary constraint; configuring both raises a RuntimeError.


- In the tested Brachistochrone optimization, the final timeseries time must be 1.8016 within a tolerance of 1.0E-4.
