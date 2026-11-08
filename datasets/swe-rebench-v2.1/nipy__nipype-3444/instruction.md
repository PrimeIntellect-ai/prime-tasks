TypeError: '<' not supported between instances of 'str' and 'int'
### Summary
Hi,

I have been following the tutorials and official documentation for nipype on registering two t1w MRIs using ANTs.

1) https://nipype.readthedocs.io/en/latest/users/examples/smri_ants_registration.html
2) https://nipype.readthedocs.io/en/1.0.3/interfaces/generated/interfaces.ants/registration.html

However after following the tutorials and writing the script. When I initialize the registration
 `reg = Registration()` the script exits with error `TypeError: '<' not supported between instances of 'str' and 'int'`. I have not been able to find anything conclusive on this issue. I found a similar issue in this repository but it was not clear how to solve the problem (https://github.com/nipy/nipype/issues/3232).
### Actual behavior
Initialization of  Registration via `reg = Registration()` results in script exiting with error `TypeError: '<' not supported between instances of 'str' and 'int'`
### Expected behavior
Script runs without throwing type error.
### How to replicate the behavior
Initialize registration. The script stops.
### Script/Workflow details
```
import numpy as np
from nipype.interfaces.ants import Registration
from nipype.interfaces.ants import ANTS

#establish paths
template = '/home/sungurea/faisal-sandbox/students/sungurea/Part2-ScaledMR/MNI305/average305_t1_tal_lin.nii'
subject = '/home/sungurea/faisal-sandbox/students/sungurea/Part1_RawMR/UK_BIOBANK_IMAGES_1000/1000106.mgz'

#Registration
reg = Registration()

reg.inputs.fixed_image = template
reg.inputs.moving_image = subject
reg.inputs.output_transform_prefix = 'thisTransform'
reg.inputs.output_warped_image = 'transformed.nii.gz'
reg.inputs.output_transform_prefix = "output_"
reg.inputs.transforms = ['Translation', 'Rigid', 'Affine', 'SyN']
reg.inputs.transform_parameters = [(0.1,), (0.1,), (0.1,), (0.2, 3.0, 0.0)]
reg.inputs.number_of_iterations = ([[10000, 111110, 11110]] * 3 +
                                   [[100, 50, 30]])
reg.inputs.dimension = 3
reg.inputs.write_composite_transform = True
reg.inputs.collapse_output_transforms = False
reg.inputs.metric = ['Mattes'] * 3 + [['Mattes', 'CC']]
reg.inputs.metric_weight = [1] * 3 + [[0.5, 0.5]]
reg.inputs.radius_or_number_of_bins = [32] * 3 + [[32, 4]]
reg.inputs.sampling_strategy = ['Regular'] * 3 + [[None, None]]
reg.inputs.sampling_percentage = [0.3] * 3 + [[None, None]]
reg.inputs.convergence_threshold = [1.e-8] * 3 + [-0.01]
reg.inputs.convergence_window_size = [20] * 3 + [5]
reg.inputs.smoothing_sigmas = [[4, 2, 1]] * 3 + [[1, 0.5, 0]]
reg.inputs.sigma_units = ['vox'] * 4
reg.inputs.shrink_factors = [[6, 4, 2]] + [[3, 2, 1]] * 2 + [[4, 2, 1]]
reg.inputs.use_estimate_learning_rate_once = [True] * 4
reg.inputs.use_histogram_matching = [False] * 3 + [True]
reg.inputs.initial_moving_transform_com = True
print(reg.cmdline)
reg.run()
```

### Traceback
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/ants/registration.py", line 1009, in __init__
    super(Registration, self).__init__(**inputs)
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/ants/base.py", line 73, in __init__
    super(ANTSCommand, self).__init__(**inputs)
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/base/core.py", line 627, in __init__
    super(CommandLine, self).__init__(**inputs)
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/base/core.py", line 197, in __init__
    unavailable_traits = self._check_version_requirements(
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/base/core.py", line 295, in _check_version_requirements
    if names and self.version:
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/ants/base.py", line 121, in version
    return Info.version()
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/base/core.py", line 1067, in version
    klass._version = klass.parse_version(raw_info)
  File "/home/sungurea/ENV/lib/python3.9/site-packages/nipype/interfaces/ants/base.py", line 47, in parse_version
    if "post" in v_string and LooseVersion(v_string) >= LooseVersion(
  File "/cvmfs/soft.computecanada.ca/easybuild/software/2020/avx2/Core/python/3.9.6/lib/python3.9/distutils/version.py", line 70, in __ge__
    c = self._cmp(other)
  File "/cvmfs/soft.computecanada.ca/easybuild/software/2020/avx2/Core/python/3.9.6/lib/python3.9/distutils/version.py", line 341, in _cmp
    if self.version < other.version:
TypeError: '<' not supported between instances of 'str' and 'int'

```
### Platform details:

<!-- Please run the following code from your shell and place the output between the triple ticks, below.
python -c "import nipype; from pprint import pprint; pprint(nipype.get_info())"
-->

```
{'commit_hash': 'b385720',
 'commit_source': 'installation',
 'networkx_version': '2.6.3',
 'nibabel_version': '3.2.1',
 'nipype_version': '1.7.0',
 'numpy_version': '1.21.0',
 'pkg_path': '/home/sungurea/ENV/lib/python3.9/site-packages/nipype',
 'scipy_version': '1.7.0',
 'sys_executable': '/home/sungurea/ENV/bin/python',
 'sys_platform': 'linux',
 'sys_version': '3.9.6 (default, Jul 12 2021, 18:23:59) \n[GCC 9.3.0]',
 'traits_version': '6.2.0'}
```

### Execution environment
python 3.9
ANTs:
- ANTs Version: v2.3.5.post79-gdb98de3
- Compiled: Jan  2 2022 15:47:47

Choose one
Container [Venv]
My python environment inside container [3.9]
My python environment outside container
