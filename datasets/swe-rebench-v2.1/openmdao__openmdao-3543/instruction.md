`connect` incorrectly marks a connection invalid based on promoted names.
### Description

In the example below, connect fails because both input and output appear to belong to group2, but in reality they are inputs and outputs of subsystems. This connection is valid if issued on `group2`, or even if promoted to the top level.

[HIDDEN]


### Example


```
import openmdao.api as om
import pytest

# Generate the components used in the tests
class Comp1(om.ExplicitComponent):

    def setup(self):
        self.add_input('x', val=1.0)
        self.add_output('y', val=1.0)

    def compute(self, inputs, outputs):
        outputs['y'] = 3 * inputs['x']


class Comp2(om.ExplicitComponent):

    def setup(self):
        self.add_input('w', val=1.0)
        self.add_output('z', val=1.0)

    def compute(self, inputs, outputs):
        outputs['z'] = 4 * inputs['w']


def test_subgroup_promoted_connection():
    """
    This example demonstrates a problem which fails with an error when trying
    to connect the variables promoted up to the same sub-group.
    """
    class Group2(om.Group):

        def setup(self):
            self.add_subsystem('comp1', Comp1(), promotes=['*'])
            self.add_subsystem('comp2', Comp2(), promotes=['*'])

    class Group1(om.Group):
        def setup(self):
            self.add_subsystem('group2', Group2())
            self.connect('group2.y', 'group2.w')

    prob = om.Problem()
    prob.model = Group1()
    prob.model.add_subsystem('group1', Group1())
    partial_msg = 'Output and input are in the same System*'
    prob.setup()


```

### OpenMDAO Version

3.39.1-dev

### Relevant environment information

_No response_

### Additional contract requirements

- A connection between variables in different subsystems must be accepted and work even when their promoted names appear to be within the same group.
- A connection whose resolved source and target belong to the same system must be rejected during problem setup; declaring the connection before setup must not itself reject it.
