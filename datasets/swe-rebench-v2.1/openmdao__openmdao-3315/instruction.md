NonlinearBlockGS Aitken relaxation is still subject to large perturbations before Aitken kicks in.
### Description

Aitken relaxation currently [doesn't kick in until the second iteration of NLBGS](https://github.com/OpenMDAO/OpenMDAO/blob/master/openmdao/solvers/nonlinear/nonlinear_block_gs.py#L150). This can cause large perturbations to the model, which is problematic for models that are particularly sensitive.



### Example

This stand-alone python code demonstrates Aitken relaxation that prohibits large steps in the process, without waiting for later iterations. Setting `use_aitken=False` will demonstrate the large initial pertubtation, and subsequent failure of the model to converge.

```python
import numpy as np


class StandaloneAitken:
    def __init__(self, use_aitken=True):
        self._use_aitken = use_aitken

        # Aitken variables
        self.theta = 0.1
        self.theta_min = 0.1
        self.theta_max = 1.0
        self.previous_update = 0.0

        # initial conditions
        self.f = 0.0
        self.dz = 0.0
        self.dz_previous = self.dz

    def run(self, nsteps):
        for i in range(nsteps):
            print('ITER', i)
            self.iterate(i)
            print()

    def iterate(self, step):
        self.f = self.dz
        dz =  -10.0 * self.f + 3.5
        if self._use_aitken:
            self.dz = self._aitken_relax(step, dz)
        else:
            self.dz = dz
        print('dz', self.dz)

    def _aitken_relax(self, step, dz_new):
        update = dz_new - self.dz
        if step > 0:
            norm2 = (np.linalg.norm(update - self.previous_update)**2.0)

            # Only update theta if the displacements changed
            if norm2 > 1e-13:
                self.theta *= 1.0 - (update - self.previous_update) * (update)/norm2
                self.theta = np.max((np.min((self.theta,self.theta_max)),self.theta_min))

        self.previous_update = update
        print('theta', self.theta)
        return self.dz + self.theta * update


if __name__ == '__main__':
    number_of_coupling_steps = 10
    driver = StandaloneAitken(use_aitken=True)
    driver.run(number_of_coupling_steps)
```

This code demonstrates the same model in OpenMDAO, and shows the large initial perturbation (dz = 31.5) before Aitken relaxation kicks in.

```python
import numpy as np
import openmdao.api as om

class Spring(om.ExplicitComponent):

    def setup(self):
        self.add_input('dz')
        self.add_output('f')
        self.z0 = 0.0

    def compute(self, inputs, outputs):
        outputs['f'] = inputs['dz'] - self.z0

class Forcer(om.ExplicitComponent):
    def setup(self):
        self.add_input('f')
        self.add_output('dz', val=0.0)

    def compute(self, inputs, outputs):
        outputs['dz'] = -10.0*inputs['f'] + 3.5
        print('dz', outputs['dz'])


class Coupled(om.Group):
    def setup(self):
        self.add_subsystem('spring', Spring())
        self.add_subsystem('forcer', Forcer())
        self.connect('spring.f', 'forcer.f')
        self.connect('forcer.dz', 'spring.dz')


def create_model():
    model = om.Group()

    nonlinear_solver = om.NonlinearBlockGS(
    maxiter=250,
    iprint=2,
    use_aitken=True,
    aitken_min_factor=0.1,
    aitken_max_factor=1.0,
    aitken_initial_factor=0.1,
    rtol=1e-7,
    atol=1e-8,
    )

    coupling = model.add_subsystem('coupled_springs', Coupled())
    coupling.nonlinear_solver = nonlinear_solver
    return model

def main():
    prob = om.Problem()
    prob.model = create_model()
    prob.setup()
    om.n2(prob, show_browser=False)
    prob.run_model()
    print('DZ =', prob['coupled_springs.forcer.dz'])

if __name__ == '__main__':
    main()
```

### OpenMDAO Version

3.34.1

### Relevant environment information

_No response_
