pip-sync 7.0.0 uninstalls pyproject-hooks
pip-sync uninstalls pyproject-hooks, which is requirement of build package and indirectly requirement of pip-tools. End result is broken pip-tools installation.

#### Environment Versions

Windows 10
Python version: Python 3.11.4
pip version: pip 23.2
pip-tools version: pip-compile, version 7.0.0

#### Steps to replicate

1. Create and activate venv
2. Install pip-tools
3. Create empty requirements.txt
4. Run: pip-sync

#### Expected result

Everything up-to-date

#### Actual result

Found existing installation: pyproject_hooks 1.0.0
Uninstalling pyproject_hooks-1.0.0:
  Successfully uninstalled pyproject_hooks-1.0.0

### Additional contract requirements

- `pip-sync` must compare installed distributions and requirements by their
  canonical package name: two names that differ only in letter case, or only in
  the use of `.`, `-` or `_` as separators, refer to the same package. For
  example `Django` and `django` are the same package, and `jaraco.classes` and
  `jaraco-classes` are the same package.
- Consequently, when the installed environment contains a distribution whose
  name is spelled differently from the corresponding requirement, `pip-sync`
  must not schedule that distribution for installation or uninstallation.
