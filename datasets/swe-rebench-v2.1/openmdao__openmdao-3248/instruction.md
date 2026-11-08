Unit ambiguity issue when using set_val
### Description

Using `set_val()` at the subsystem level doesn't register `set_input_defaults()` being called. If two subsystems promote a variable to the same variable name but have different units at the subsystems, this can cause an issue depending on what level `set_val()` is called. In the example below, using `p.set_val('comp.x', 2.0, units='m')` works but using `comp.set_val('x', 2.0, units='m')` causes the error

`The following inputs, ['comp.ec1.x', 'comp.ec2.x'], promoted to 'x', are connected but their metadata entries ['units'] differ. Call <group>.set_input_defaults('x', units=?), where <group> is the Group named 'comp' to remove the ambiguity.`

### Example

`class Comp(om.Group):`
`    def setup(self):`
`        self.add_subsystem('ec1', om.ExecComp('y=x', x={'units': 'm'}), promotes_inputs=['x'])`
`        self.add_subsystem('ec2', om.ExecComp('z=x**2', x={'units': 'ft'}), promotes_inputs=['x'])`
`        self.set_input_defaults('x', val=1.0, units='m')`


`if __name__ == '__main__':`
`    p = om.Problem(om.Group())`
`    comp = p.model.add_subsystem('comp', Comp())`
`    p.setup()`
`    # p.set_val('comp.x', 2.0, units='m')`
`    comp.set_val('x', 2.0, units='m')`
`    p.run_model()`


### OpenMDAO Version

3.32.1-dev

### Relevant environment information

_No response_
