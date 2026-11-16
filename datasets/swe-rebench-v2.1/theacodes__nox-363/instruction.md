Use 'python -m pip' instead of 'pip' for package installs.
**How would this feature be useful?**
Using 'python -m pip' makes sure that the package installation is going into the expected python environment.

**Describe the solution you'd like**
[HIDDEN] is where the install command runs 'pip'. I think a good solution would be to have the nox work simply run 'python -m pip' instead.
