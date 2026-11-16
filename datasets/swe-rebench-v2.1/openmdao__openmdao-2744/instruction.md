Drivers issue warning regarding removal of a nonexistent hook.
### Description

I consistently see the following warning messages from the `_remove_hook` function when using pyOptSparseDriver or ScipyOptimizeDriver:

```
.../openmdao/utils/hooks.py:266: OpenMDAOWarning:Couldn't find the given 'post' function in the post hooks for Driver._compute_totals.
.../openmdao/utils/hooks.py:266: OpenMDAOWarning:Couldn't find the given 'post' function in the post hooks for Driver._get_coloring.
```

The example below is from [this pyoptsparse driver test](https://github.com/OpenMDAO/OpenMDAO/blob/85a5a264d3f92ebeed85fb85f9b62a54cd3e2ff3/openmdao/drivers/tests/test_pyoptsparse_driver.py), but any optimization should exhibit this behavior.


### Example

```python
import openmdao.api as om

from openmdao.utils.assert_utils import assert_near_equal


prob = om.Problem()
model = prob.model

model.set_input_defaults('x', 50.0)
model.set_input_defaults('y', 50.0)

parab = om.ExecComp('f_xy = (x-3.0)**2 + x*y + (y+4.0)**2 - 3.0')

model.add_subsystem('comp', parab, promotes=['*'])
model.add_subsystem('con', om.ExecComp('c = x + y - 25.0'), promotes=['*'])

prob.set_solver_print(level=0)

prob.driver = om.pyOptSparseDriver()
prob.driver.options['optimizer'] = OPTIMIZER

model.add_design_var('x', lower=-50.0, upper=50.0)
model.add_design_var('y', lower=-50.0, upper=50.0)
model.add_objective('f_xy')
model.add_constraint('c', equals=0.0, linear=True)

prob.setup()

prob.run_driver()

assert_near_equal(prob['x'], 19.5, 1e-6)
assert_near_equal(prob['y'], 5.5, 1e-6)
```


### OpenMDAO Version

3.22.1-dev

### Relevant environment information

_No response_
