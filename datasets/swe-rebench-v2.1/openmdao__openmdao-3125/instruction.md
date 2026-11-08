Registering a hook function in a derived class wipes out any hooks already registered in the base class.
### Description

See title.

### Example


import openmdao.api as om
import openmdao.utils.hooks as hooks


def build_model(name='problem1', prob=None):
    if prob is None:
        prob = om.Problem(name=name)
    prob.calls = []
    model = prob.model

    model.add_subsystem('p1', om.IndepVarComp('x', 3.0))
    model.add_subsystem('p2', om.IndepVarComp('y', -4.0))
    model.add_subsystem('comp', om.ExecComp("f_xy=2.0*x+3.0*y"))

    model.connect('p1.x', 'comp.x')
    model.connect('p2.y', 'comp.y')
    prob.setup()
    return prob


def main():
    def inherited_hook_pre(prob, **kwargs):
        prob.calls.append('inherited_pre')

    def inherited_hook_post(prob, **kwargs):
        prob.calls.append('inherited_post')

    def base_hook_pre(prob, **kwargs):
        prob.calls.append('base_pre')

    def base_hook_post(prob, **kwargs):
        prob.calls.append('base_post')

    hooks._register_hook('final_setup', 'MyProblem', pre=inherited_hook_pre, post=inherited_hook_post)
    hooks._register_hook('final_setup', 'Problem', pre=base_hook_pre, post=base_hook_post)

    prob = MyProblem()
    build_model(prob=prob)

    prob.run_model()
    prob.run_model()
    prob.run_model()

    assert prob.calls == ['inherited_pre', 'base_pre', 'inherited_post', 'base_post', 'inherited_pre',
                                    'base_pre', 'inherited_post', 'base_post', 'inherited_pre', 'base_pre', 'inherited_post', 'base_post']

    hooks._unregister_hook('final_setup', 'Problem', pre=base_hook_pre, post=False)

    prob.calls = []

    prob.run_model()
    prob.run_model()

    assert prob.calls == ['inherited_pre', 'inherited_post', 'base_post', 'inherited_pre', 'inherited_post', 'base_post']


class MyProblem(om.Problem):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.calls = []

    def run_model(self):
        super().run_model()


main()


### OpenMDAO Version

3.30.1

### Relevant environment information

_No response_
