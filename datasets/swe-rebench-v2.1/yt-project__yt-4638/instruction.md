1 is not treated as dimensionless
<!--To help us understand and resolve your issue, please fill out the form to
the best of your ability.-->
<!--You can feel free to delete the sections that do not apply.-->

### Bug report

**Bug summary**

Adding a dimensionless field to a dataset using `units="auto",   dimensions=yt.units.dimensionless` raises a `YTDimensionalityError`.

**Code for reproduction**

```python
import yt
import yt.testing

ds = yt.testing.fake_amr_ds(fields=[("gas", "density")], units=["g/cm**3"])

def _dimensionless_field(field,data):
    return (data[("gas", "density")] / data[("gas", "density")])

ds.add_field(
    name=("gas", "ones"),
    function=_dimensionless_field,
    sampling_type="local",
    units="auto",
    dimensions=yt.units.dimensionless
)

p = yt.SlicePlot(ds,"x",("gas", "ones"))
```

**Actual outcome**



<!--The output produced by the above code, which may be a screenshot, console
output, etc.-->

```python-log
yt : [INFO     ] 2023-08-18 11:28:07,929 Parameters: current_time              = 0.0
yt : [INFO     ] 2023-08-18 11:28:07,929 Parameters: domain_dimensions         = [32 32 32]
yt : [INFO     ] 2023-08-18 11:28:07,929 Parameters: domain_left_edge          = [0. 0. 0.]
yt : [INFO     ] 2023-08-18 11:28:07,930 Parameters: domain_right_edge         = [1. 1. 1.]
yt : [INFO     ] 2023-08-18 11:28:07,930 Parameters: cosmological_simulation   = 0
Traceback (most recent call last):
  File "/.../.../repro.py", line 17, in <module>
    p = yt.SlicePlot(ds,"x",("gas", "ones"))
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/username/.pyenv/versions/Sciences-3.11.2/lib/python3.11/site-packages/yt/visualization/plot_window.py", line 1833, in __init__
    slc.get_data(fields)
  File "/home/username/.pyenv/versions/Sciences-3.11.2/lib/python3.11/site-packages/yt/data_objects/selection_objects/data_selection_objects.py", line 221, in get_data
    self._generate_fields(fields_to_generate)
  File "/home/username/.pyenv/versions/Sciences-3.11.2/lib/python3.11/site-packages/yt/data_objects/selection_objects/data_selection_objects.py", line 270, in _generate_fields
    raise YTDimensionalityError(fi.dimensions, dimensions)
yt.utilities.exceptions.YTDimensionalityError: Dimensionality specified was dimensionless but we need 1

```

**Expected outcome**

The same output as when using `units=""`, that is just some yt infos and no error.

```python-log
yt : [INFO     ] 2023-08-18 11:26:54,562 Parameters: current_time              = 0.0
yt : [INFO     ] 2023-08-18 11:26:54,563 Parameters: domain_dimensions         = [32 32 32]
yt : [INFO     ] 2023-08-18 11:26:54,563 Parameters: domain_left_edge          = [0. 0. 0.]
yt : [INFO     ] 2023-08-18 11:26:54,564 Parameters: domain_right_edge         = [1. 1. 1.]
yt : [INFO     ] 2023-08-18 11:26:54,565 Parameters: cosmological_simulation   = 0
yt : [INFO     ] 2023-08-18 11:26:54,826 xlim = 0.000000 1.000000
yt : [INFO     ] 2023-08-18 11:26:54,827 ylim = 0.000000 1.000000
yt : [INFO     ] 2023-08-18 11:26:54,829 xlim = 0.000000 1.000000
yt : [INFO     ] 2023-08-18 11:26:54,829 ylim = 0.000000 1.000000
yt : [INFO     ] 2023-08-18 11:26:54,830 Making a fixed resolution buffer of (('gas', 'ones')) 800 by 800
```


**Version Information**
<!--Please specify your platform and versions of the relevant libraries you are
using:-->
  * Operating System: Linux 5.10.0-24-amd64, Debian 5.10.179-5 (2023-08-08) x86_64 GNU/Linux
  * Python Version: 3.11.2
  * yt version: 4.2.1 (installed with pip)
