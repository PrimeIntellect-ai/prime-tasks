AutoIVC and src_indices errors upon run_model
### Description

I've ran into two separate (but maybe related) bugs lately, which I was able to reproduce with the provided example script. Both occur during run_model, not setup.

The first is that, when some group's component input is unconnected, I get the error
```
Traceback (most recent call last):
  File "/lustre3/hpnobackup2/asthelen/Codes/Testing/OM_bugs/ivc/main.py", line 22, in <module>
    prob.run_model()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/problem.py", line 680, in run_model
    self.final_setup()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/problem.py", line 1088, in final_setup
    model._setup_part2()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/group.py", line 1103, in _setup_part2
    self._resolve_group_input_defaults()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/group.py", line 1909, in _resolve_group_input_defaults
    top_origin = paths[0][1]
IndexError: list index out of range
```
It looks like in the n2, the two components' ```in1``` inputs get turned into AutoIVCs as they're supposed to... the model just can't be ran.

If you uncomment the two connect lines in the example, then I get this other error:
```
Traceback (most recent call last):
  File "/lustre3/hpnobackup2/asthelen/Codes/Testing/OM_bugs/ivc/main.py", line 22, in <module>
    prob.run_model()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/problem.py", line 680, in run_model
    self.final_setup()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/problem.py", line 1089, in final_setup
    self._check_collected_errors()
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/problem.py", line 638, in _check_collected_errors
    raise exc_type('\n'.join(final_msg)).with_traceback(tback)
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/core/group.py", line 1641, in _resolve_src_indices
    sinds = convert_src_inds(current_pinfo.src_indices, current_pinfo.src_shape,
  File "/hpnobackup2/asthelen/Codes/Repositories/OM_test/OpenMDAO_2025jan24/openmdao/utils/general_utils.py", line 1184, in convert_src_inds
    return parent_src_inds.shaped_array(flat=True)[my_src_inds.flat()]
IndexError:
Collected errors for problem 'main':
   <model> <class Top>: When connecting 'ivc.in1' to 'comp2.in1': input 'comp2.in1' src_indices are [1] and indexing into those failed using src_indices [1] from input 'comp2.in1'. Error was: index 1 is out of bounds for axis 0 with size 1
```
It's only an issue with src_indices=[1] and not [0], so if you set them both to [0] then the error doesn't occur.

### Example

```
import numpy as np
import openmdao.api as om

class Comp(om.ExplicitComponent):
    def setup(self):
        self.add_input("in1", val=1.)
        self.add_output("out1", val=1.)

class Top(om.Group):
    def setup(self):
        self.add_subsystem("ivc", om.IndepVarComp(), promotes=["*"])
        self.ivc.add_output("in1", [1.,1.])
        self.add_subsystem("comp1", Comp())
        self.add_subsystem("comp2", Comp())

        #self.connect("in1", "comp1.in1", src_indices=[0])
        #self.connect("in1", "comp2.in1", src_indices=[1])

prob = om.Problem()
prob.model = Top()
prob.setup(mode='rev')
om.n2(prob, show_browser=False, outfile='n2.html')
prob.run_model()
```

### OpenMDAO Version

3.38.1-dev

### Relevant environment information

_No response_
