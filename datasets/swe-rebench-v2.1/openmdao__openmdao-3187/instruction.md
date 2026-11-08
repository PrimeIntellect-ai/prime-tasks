Constraints in differential_evolution of ScipyOptimizeDriver
### Description

Hello, I found that scipy's help document says that differential_evolution supports constraints. But I found differential_evolution in ScipyOptimizeDriver  doesn't not support.

Differential evolution originally did not support constraints but that was changed in Scipy 1.4.

OpenMDAO should allow constraints to be passed to ScipyOptimizeDriver when using `differential_evolution`.

### Example

The following test should function based on Scipy's documentation:

```
    @unittest.skipUnless(Version(scipy_version) >= Version("1.4"),
                         "scipy >= 1.4 is required.")
    def test_differential_evolution_constrained(self):
        # Source of example:
        # https://docs.scipy.org/doc/scipy/reference/generated/scipy.optimize.differential_evolution.html
        # In this example the minimum is not the unbounded global minimum.

        size = 2

        prob = om.Problem()
        model = prob.model

        model.add_subsystem('rosen', Rosenbrock(vec_size=size), promotes=['*'])
        model.add_subsystem('constraint_comp',
                            om.ExecComp('con = sum(x)', con = {'shape': (1,)}, x = {'shape': (size)}),
                            promotes=['*'])

        prob.driver = driver = om.ScipyOptimizeDriver()
        driver.options['optimizer'] = 'differential_evolution'
        driver.options['disp'] = True
        driver.opt_settings['seed'] = 1

        model.add_design_var('x', lower=0, upper=2)
        model.add_constraint('con', upper=1.9, linear=True)
        model.add_objective('f')
        prob.setup()
        prob.run_driver()
        print(prob['con'])
        assert_near_equal(prob['x'], [0.96632622, 0.93367155], 1e-2)
        assert_near_equal(prob['f'], 0.0011352416852625719, 1e-2)
```

### OpenMDAO Version

3.31.1

### Relevant environment information

_No response_
