[bug] Issue when running DC powerflow after AC powerflow
<!--- **PLEASE READ:** When submitting here, please ensure you've completed the following checklist and checked the boxes to confirm. Bug reports without it may be closed. Thanks! --->

### Issue Report Checklist

* [X] Searched the [issues page](https://github.com/e2nIEE/pandapower/issues) for similar reports
* [X] Read the relevant sections of the [documentation](https://pandapower.readthedocs.io/en/latest/about.html)
* [X] Browse the [tutorials](https://github.com/e2nIEE/pandapower/tree/develop/tutorials) and [tests](https://github.com/e2nIEE/pandapower/tree/develop/pandapower/test) for usefull code snippets and examples of use
* [X] Reproduced the issue after updating with `pip install --upgrade pandapower` (or `git pull`)
* [X] Tried basic troubleshooting (if a bug/error)
    * [X] Restarted interpreter
    * [X] Checked the pythonpath
* [X] Completed the **Problem Description**, **What steps reproduce the problem** and **Versions** sections below


## Problem Description

When I run a DC powerflow after an AC powerflow, some columns of the `net.res_bus` (such as `vm_pu` and `q_mvar`) does not seem to be "updated" with the powerflow results.

This results in strange behaviour such as (see reproducible code below) `net.res_line["vm_from_pu"]` which is not equal to `net.res_bus.iloc[THE BUS WHERE THE LINE IS CONNECTED]["vm_pu"]`.

The doc (see *eg* https://pandapower.readthedocs.io/en/latest/elements/line.html#result-parameters) clearly specify : `vm_from_pu: voltage magnitude at from bus` which is not the case in the example.


### What steps reproduce the problem?

1.  install pandapower
2. run the code

### What is the expected output? What do you see instead?

If you look at the bus to which a line is connected and the value of "vm_from_pu" then there should not be a difference. The voltage magnitude is unique at a given bus.

```python
import pandapower as pp
import pandapower.networks as pn
import numpy as np

def get_installed_versions():
    res = []
    import pandapower as pp
    res.append(f"* pandapower version: {pp.__version__}")
    import pandas as pd
    res.append(f"* pandas version: {pd.__version__}")
    import networkx
    res.append(f"* networkx version: {networkx.__version__}")
    import scipy
    res.append(f"* scipy version: {scipy.__version__}")
    import numpy as np
    res.append(f"* numpy version: {np.__version__}")
    import packaging
    res.append(f"* packaging version: {packaging.__version__}")
    import tqdm
    res.append(f"* tqdm version: {tqdm.__version__}")
    import deepdiff
    res.append(f"* deepdiff version: {deepdiff.__version__}")
    return "\n".join(res)
print(get_installed_versions())

# now the test
net = pn.case14()

line_id = 6
# run an ac powerflow (simple setting)
pp.runpp(net, init="flat", lightsim2grid=False, distributed_slack=False)
# normal behaviour (see below for detail about this line of code)
from_bus, to_bus = net.line.iloc[line_id][["from_bus", "to_bus"]]
assert np.allclose(net.res_bus.iloc[[from_bus, to_bus]]["vm_pu"].values,
                   net.res_line.iloc[line_id][["vm_from_pu", "vm_to_pu"]].values)

# then run a dc powerflow
pp.rundcpp(net)
assert( net.res_line.iloc[line_id][["vm_from_pu", "vm_to_pu"]] == [1.0, 1.0]).all()
net.line.iloc[line_id][["from_bus", "to_bus"]]  # [3, 4]
from_bus, to_bus = net.line.iloc[line_id][["from_bus", "to_bus"]]  # [3, 4]
assert from_bus == 3
assert to_bus == 4
assert np.allclose(net.res_bus.iloc[[3, 4]]["vm_pu"], [1.017671, 1.019514])

# weird behaviour (same as above, in one line of code)
assert np.allclose(net.res_bus.iloc[[from_bus, to_bus]]["vm_pu"].values,
                   net.res_line.iloc[line_id][["vm_from_pu", "vm_to_pu"]].values)

```

### Paste Traceback/Error Below (if applicable)
<!--- Copy from error dialog or View > Panes > Internal Console --->

```python-traceback
Traceback (most recent call last):
  File "test_pp_dc.py", line 48, in <module>
    assert np.allclose(net.res_bus.iloc[[from_bus, to_bus]]["vm_pu"].values,
AssertionError
```

## Versions
<!--- You can get this information from the "pip list" or "conda list" command
from the Anaconda Prompt/Terminal/command line . --->

* pandapower version: 2.12.1
* pandas version: 1.5.3
* networkx version: 2.5
* scipy version: 1.6.0
* numpy version: 1.20.3
* packaging version: 20.9
* tqdm version: 4.61.2
* deepdiff version: 6.2.1
* Operating System name/version: ubuntu 20.04

ps. it whould be nice to have a helper function from pandapower from which we could copy paste results above. Such as:
```python
import pandapower as pp
print(pp.get_installed_versions())
```

And somewhere in pandapower you define:

```python
def get_installed_versions():
    res = []
    import pandapower as pp
    res.append(f"* pandapower version: {pp.__version__}")
    import pandas as pd
    res.append(f"* pandas version: {pd.__version__}")
    import networkx
    res.append(f"* networkx version: {networkx.__version__}")
    import scipy
    res.append(f"* scipy version: {scipy.__version__}")
    import numpy as np
    res.append(f"* numpy version: {np.__version__}")
    import packaging
    res.append(f"* packaging version: {packaging.__version__}")
    import tqdm
    res.append(f"* tqdm version: {tqdm.__version__}")
    import deepdiff
    res.append(f"* deepdiff version: {deepdiff.__version__}")
    return "\n".join(res)
```

## Labels (if access available)
* [X] Choose a `labels` at the right side (e.g. `bug`, `controller`, `OPF`...)
