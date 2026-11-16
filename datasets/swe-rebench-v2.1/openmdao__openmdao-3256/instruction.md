Key error when getting recorded constraints from a case recorder which did not record all the constraints
### Description

Hi,

When trying to  get the constraints from a case  in which only some constraints are recorded (using `recording_options['includes']`) OpenMDAO raises a KeyError exception. It seems that it tries to get all the constraints that were defined in the problem, even those that were not recorded.

Thanks for your help!

### Example

```python
import openmdao.api as om
import numpy as np

class MyGroup(om.Group):
    def setup(self):
        self.add_subsystem('dvs', om.IndepVarComp(), promotes=['*'])
        self.add_subsystem('my_comp', MyComponent(), promotes=['*'])
        self.dvs.add_output('x', val=np.ones(10))
        self.add_design_var('x', lower=0.0, upper=1.0)
        self.add_constraint('y_0', equals=0)
        self.add_constraint('y_1', equals=0)
        self.add_objective('z')

class MyComponent(om.ExplicitComponent):
    def setup(self):
        self.add_input('x', val=np.ones(10))
        self.add_output('y_0', val=np.ones(3))
        self.add_output('y_1', val=np.ones(7))
        self.add_output('z', val=1.0, shape=1)

prob = om.Problem(model=MyGroup(), driver=om.ScipyOptimizeDriver(optimizer='SLSQP', tol=1e-4, disp=True, maxiter=1))
prob.model.recording_options['includes'] = ['x', 'y_0', 'z']
prob.model.add_recorder(om.SqliteRecorder('cases.sql'))
prob.setup(mode='rev')
prob.run_driver()

case = om.CaseReader('cases.sql').get_case(0)
print(case.get_constraints())
```

This example should return a dictionary containing the constraint `y_0`, but it raises the following error:
```
Traceback (most recent call last):
  File "run.py", line 28, in <module>
    print(case.get_constraints())
  File "openmdao/recorders/case.py", line 375, in get_constraints
    return self._get_variables_of_type('constraint', scaled, use_indices)
  File "openmdao/recorders/case.py", line 883, in _get_variables_of_type
    val = self.outputs[src].copy()
  File "openmdao/recorders/case.py", line 1115, in __getitem__
    raise KeyError('Variable name "%s" not found.' % key)
KeyError: 'Variable name "my_comp.y_1" not found.'
```

### OpenMDAO Version

since 3.31

### Relevant environment information

_No response_
