Case._get_units method unable to get units for some variables.
### Description

In some cases the Case._get_units method cannot find the units for variable and raises an exception. But information about the units can be found in [HIDDEN].  It is just not being used.


### Example

This script shows how the units for a variable can be gotten from the problem_metadata and also how the _get_units method fails to get it. This script works with the attached file. Just need to unzip the attachment.

```
from openmdao.recorders.sqlite_reader import SqliteCaseReader
cr = SqliteCaseReader('driver_history.sql')
case = cr.get_case(0)

name = 'traj.phases.accel->final_boundary_constraint->EAS'

units_from_problem_metadata = [HIDDEN]
print(f"{units_from_problem_metadata=}")

units = case._get_units(name)
```








### OpenMDAO Version

3.36.1-dev

### Relevant environment information

_No response_

### Additional contract requirements

- When recorded variable metadata provides units for a name that `Case._get_units(name)` cannot otherwise resolve, the method must return those units rather than raise an exception.
- When an objective is registered with an alias using `Group.add_objective(..., alias=...)`, `Case._get_units` must return the same units for the alias as for the underlying objective.
