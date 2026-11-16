AddSubtractComp allows the same input multiple times
### Description

It is possible to define an input multiple times when using the 'AddSubtractComp'. This is confusing as it double-counts that value.

I would appreciate at least a warning if that happens.

### Example

    import openmdao.api as om

    def opt_paraboloid(add_input_twice):
        # build the model
        prob = om.Problem()

        prob.model.add_subsystem('f1', om.ExecComp('f1 = (x-3)**2'))
        prob.model.add_subsystem('f2', om.ExecComp('f2 = (y+4)**2 - 3'))
        paraboloid = om.AddSubtractComp()

        # Here, it is possible to add the same input (f2) twice
        input_names = ["f1", "f2"]
        if add_input_twice:
            input_names.append('f2')
        paraboloid.add_equation( "f", input_names=input_names)
        prob.model.add_subsystem('paraboloid', paraboloid)

        # setup the optimization
        prob.driver = om.ScipyOptimizeDriver()
        prob.driver.options['optimizer'] = 'SLSQP'

        prob.model.add_design_var('f1.x', lower=-50, upper=50)
        prob.model.add_design_var('f2.y', lower=-50, upper=50)
        prob.model.add_objective('paraboloid.f')

        prob.setup()

                                                                                                                                                                                                                                                                                                                                                                                                            # Set initial values.
        prob.set_val('f1.x', 3.0)
        prob.set_val('f2.y', -4.0)

        # run the optimization
        prob.run_driver()

        # minimum value
        print(prob.get_val('paraboloid.f'))

        # location of the minimum
        print(prob.get_val('f1.x'))
        print(prob.get_val('f2.y'))


    if __name__ == '__main__':
        opt_paraboloid(False)
        opt_paraboloid(True)

### OpenMDAO Version

3.31.1

### Relevant environment information

_No response_

### Additional contract requirements

- When `AddSubtractComp.add_equation` is called with duplicate entries in `input_names`, issue an `OpenMDAOWarning` with the message `Duplicate inputs are connected to '{output_name}'. This will double count the same value, which may cause unexpected behavior.`, replacing `{output_name}` with the equation's output name.
