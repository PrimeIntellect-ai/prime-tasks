`list_indep_vars` returns duplicates in some instances.
### Description

When a system has multiple inputs connected to the same IVC, `list_indep_vars` will return a list containing the promoted name multiple times.

### Example

```python
def test_list_indep_vars_duplicate_inputs(self):
        prob = om.Problem()
        prob.model.add_subsystem('a', om.ExecComp('y = x**2'),
                                 promotes_inputs=['x'], promotes_outputs=['y'])

        prob.model.add_subsystem('b', om.ExecComp('z = x**3'),
                                 promotes_inputs=['x'], promotes_outputs=['z'])

        prob.model.add_design_var('x', lower=-1, upper=1)
        prob.model.add_objective('y')

        prob.setup()

        prob.final_setup()

        indep_vars = prob.list_indep_vars()

        self.assertEqual(len(indep_vars), 1)
```


### OpenMDAO Version

3.26.1-dev

### Relevant environment information

_No response_
