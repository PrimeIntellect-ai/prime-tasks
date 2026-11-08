conda: support for Mamba
**How would this feature be useful?**

It would be great to support `mamba`, which is a conda replacement solver that is dramatically faster. A solve of a complex package like ROOT (which is a reason to use conda in the first place) takes several minutes with conda, and a few seconds with mamba.

**Describe the solution you'd like**

Option 1: Provide a new backend: `"mamba"`. This would simply make `conda_install(...)` use mamba instead of conda. This is the best option I could think of.

Option 2: Automatically use mamba if available over conda. This is slightly too magical, and there are _minute_ difference in the solve (that shouldn't matter).

Option 3: Add a setting to select the command used for conda. I don't think there is a good reason to generalize too much - mamba is a drop-in replacement for part of conda (other parts can just use conda, as it's always available with mamba).

This was mentioned in https://github.com/theacodes/nox/issues/346#issue-695644289 as a side note, but never attempted.
