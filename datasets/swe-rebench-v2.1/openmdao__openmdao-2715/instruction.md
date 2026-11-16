Change default for Driver option supports['optimization'] to False
### Desired capability or behavior.

The `supports['optimization']` option currently  [defaults](https://github.com/OpenMDAO/OpenMDAO/blob/master/openmdao/core/driver.py#L163) to `True` in the Driver base class.

This is actually incorrect, as the base class itself does not support optimization.

The default should be changed to `False` and Driver sub-classes should set it appropriately.

This is technically a backward incompatible change for outside developers that may have developed their own drivers.  However, this option was only added 4 months ago, specifically to support the optimization report, so the impact should only be that non-OpenMDAO drivers that rely on the default would not auto-generate an Optimization report unless updated to set the option to `True`.

### Associated POEM

N/A
