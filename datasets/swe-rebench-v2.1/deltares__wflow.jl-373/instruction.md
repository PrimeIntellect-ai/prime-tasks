Remove lower limit of zero for `sbm.runoff`
### Feature type

Changing existing functionality

### Improvement Description

The lower limit of `runoff` of the `SBM` concept is set at zero. This was implemented in the Python version of wflow_sbm, to avoid a very slow kinematic wave solution for surface flow computation (no distinction between a kinematic wave for overland and river flow). When in the Python version of wflow_sbm the kinematic wave for surface flow was split into a river and land component, the lower limit was removed for river runoff, but not for land runoff. It would be good to also remove this lower limit for land runoff, also because it may result in water balance errors.

### Implementation Description

Remove lower limit of zero for `sbm.runoff`.

### Additional Context

_No response_

### Additional contract requirements

- The `SBM` vertical concept exposes a new state/output variable `net_runoff`, the net
  surface runoff, defined as the surface runoff `runoff` minus the actual open water
  evaporation `ae_openw_l`.
- The `runoff` variable is redefined as the total land runoff (the surface runoff from
  infiltration and saturation excess, before subtracting `ae_openw_l`).
- The lower limit of zero is removed from the net surface runoff quantity (`net_runoff`).
- The new `net_runoff` variable is exposed through the BMI exchange interface, so the
  number of BMI input and output items increases by one.
