FLops tabular aero is not working with training data.
### Description

Looks like we have a test in `test_tabular_aero_group.py` for passing the drag dependent and independent polars into the mission drag interps, but the test is incorrectly passing.

### Example

see TabularAeroGroupDataTest in test_tabular_aero_group

### Aviary Version

0.9.4-dev

### Relevant environment information

_No response_

### Additional contract requirements

- The FLOPS-based tabular aerodynamics method must accept the zero-lift and lift-dependent drag polars as aircraft design variables: `aircraft:design:lift_independent_drag_polar` (`Aircraft.Design.LIFT_INDEPENDENT_DRAG_POLAR`) carries the zero-lift drag coefficient training data and `aircraft:design:lift_dependent_drag_polar` (`Aircraft.Design.LIFT_DEPENDENT_DRAG_POLAR`) carries the lift-dependent drag coefficient training data. Both names must exist in the variable hierarchy.
- When the tabular aerodynamics group is built with the `connect_training_data` option set to True, the values supplied for these two design variables must be the data used by the mission drag interpolators, so that changing them changes the computed drag. The tables passed as `CD0_data` and `CDI_data` are not used in that mode.
- With `connect_training_data` left at its default, the tabular aerodynamics group continues to interpolate from the `CD0_data` and `CDI_data` tables, as before.
